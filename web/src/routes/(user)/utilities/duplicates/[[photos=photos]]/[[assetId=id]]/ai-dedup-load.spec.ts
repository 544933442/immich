import { beforeEach, describe, expect, it, vi } from 'vitest';

// QA 集成测试：A1 / D1 / S1。用 mock SDK 真实执行 `+page.ts` 的 load()，
// 分别验证关闭态与开启态：关闭态在 evaluate 之前短路；开启态把 AI 推荐
// 覆盖到内存副本的 keep ids，且不改变既有契约。

const mocks = vi.hoisted(() => ({
  getAssetDuplicates: vi.fn(),
  getAiDedupPrompt: vi.fn(),
  evaluateAiDedup: vi.fn(),
  authenticate: vi.fn(),
  getFormatter: vi.fn(),
}));

vi.mock('@immich/sdk', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@immich/sdk')>()),
  getAssetDuplicates: mocks.getAssetDuplicates,
  getAiDedupPrompt: mocks.getAiDedupPrompt,
  evaluateAiDedup: mocks.evaluateAiDedup,
}));

vi.mock('#lib/utils/auth.ts', () => ({ authenticate: mocks.authenticate }));
vi.mock('#lib/utils/i18n.ts', () => ({ getFormatter: mocks.getFormatter }));

const officialDuplicates = () => [
  { duplicateId: 'g1', suggestedKeepAssetIds: ['a1'], assets: [{ id: 'a1' }, { id: 'a2' }] },
  { duplicateId: 'g2', suggestedKeepAssetIds: ['b1'], assets: [{ id: 'b1' }, { id: 'b2' }] },
];

const aiResult = (overrides: Record<string, unknown> = {}) => ({
  degraded: false,
  degradeReason: null,
  duplicateId: 'g1',
  generatedAt: '2026-01-01T00:00:00.000Z',
  indexMap: {},
  model: 'gpt-4o',
  needsManualReview: false,
  promptVersion: 'ai-dedup-prompt-v1.0',
  recommendedKeepAssetIds: ['a2'],
  results: [],
  strategyApplied: false,
  summary: '',
  truncated: false,
  ...overrides,
});

const evaluateResponse = (results: unknown[]) => ({
  degradedCount: 0,
  quota: { limit: 200, used: 0 },
  results,
  truncatedCount: 0,
});

const prompt = (overrides: Record<string, unknown> = {}) => ({
  enabled: true,
  promptVersion: 'ai-dedup-prompt-v1.0',
  strategyHint: '',
  strategySummary: '',
  trashEnabled: true,
  ...overrides,
});

const runLoad = async (index?: number) => {
  const { load } = await import('./+page.ts');
  const url = new URL('http://localhost/utilities/duplicates');
  if (index !== undefined) {
    url.searchParams.set('index', String(index));
  }
  return load({ url } as never);
};

beforeEach(() => {
  vi.clearAllMocks();
  mocks.authenticate.mockResolvedValue(undefined);
  mocks.getFormatter.mockResolvedValue((key: string) => key);
  mocks.getAssetDuplicates.mockResolvedValue(officialDuplicates());
});

describe('A1 关闭态（真实 load 两态分别运行）', () => {
  it('enabled=false 时零 evaluate 调用，返回官方启发式预选与空 AI 上下文', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt({ enabled: false }));

    const data = await runLoad();

    expect(mocks.getAiDedupPrompt).toHaveBeenCalledTimes(1);
    expect(mocks.evaluateAiDedup).not.toHaveBeenCalled();
    expect(data.aiEnabled).toBe(false);
    expect(data.aiResults).toEqual({});
    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
    expect(data.duplicates[1].suggestedKeepAssetIds).toEqual(['b1']);
    expect(data.meta.title).toBe('duplicates');
  });

  it('/prompt 抛错（S1 端点不可用）时同样短路，不抛异常、不改预选', async () => {
    mocks.getAiDedupPrompt.mockRejectedValue(new Error('service unavailable'));

    const data = await runLoad();

    expect(mocks.evaluateAiDedup).not.toHaveBeenCalled();
    expect(data.aiEnabled).toBe(false);
    expect(data.aiPrompt).toBeNull();
    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
  });
});

describe('D1 启用态（真实 load 两态分别运行）', () => {
  it('enabled=true 时调用 evaluate 并用 AI 推荐覆盖内存副本的 keep ids', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.evaluateAiDedup.mockResolvedValue(evaluateResponse([aiResult()]));

    const data = await runLoad();

    expect(mocks.evaluateAiDedup).toHaveBeenCalledTimes(1);
    expect(mocks.evaluateAiDedup.mock.calls[0][0]).toEqual({
      aiDedupEvaluateDto: { duplicateIds: ['g1', 'g2'] },
    });
    expect(data.aiEnabled).toBe(true);
    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a2']);
    expect(data.duplicates[1].suggestedKeepAssetIds).toEqual(['b1']);
    expect(Object.keys(data.aiResults)).toEqual(['g1']);
    expect(data.aiPrompt?.enabled).toBe(true);
  });

  it('evaluate 失败时保持官方启发式、aiEnabled=false 且 load 不抛错', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.evaluateAiDedup.mockRejectedValue(new Error('provider timeout'));

    const data = await runLoad();

    expect(data.aiEnabled).toBe(false);
    expect(data.aiResults).toEqual({});
    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('degraded / 低置信组不被覆盖（S4 / S10），自信组仍被覆盖', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.evaluateAiDedup.mockResolvedValue(
      evaluateResponse([
        aiResult({ duplicateId: 'g1', degraded: true, degradeReason: 'PROVIDER_ERROR' }),
        aiResult({ duplicateId: 'g2', recommendedKeepAssetIds: ['b2'] }),
      ]),
    );

    const data = await runLoad();

    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
    expect(data.duplicates[1].suggestedKeepAssetIds).toEqual(['b2']);
  });

  it('needsManualReview / 空推荐集合均不覆盖启发式预选', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.evaluateAiDedup.mockResolvedValue(
      evaluateResponse([
        aiResult({ needsManualReview: true }),
        aiResult({ duplicateId: 'g2', recommendedKeepAssetIds: [] }),
      ]),
    );

    const data = await runLoad();

    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
    expect(data.duplicates[1].suggestedKeepAssetIds).toEqual(['b1']);
  });

  it('模型幻觉的 assetId 被剔除，不会导致误删（C1）', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.evaluateAiDedup.mockResolvedValue(
      evaluateResponse([aiResult({ recommendedKeepAssetIds: ['not-in-group'] })]),
    );

    const data = await runLoad();

    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('trashEnabled=false 由 prompt 端点回传给页面（R-11 前置条件）', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt({ trashEnabled: false }));
    mocks.evaluateAiDedup.mockResolvedValue(evaluateResponse([aiResult()]));

    const data = await runLoad();

    expect(data.aiPrompt?.trashEnabled).toBe(false);
    expect(data.aiEnabled).toBe(true);
  });
});

describe('懒评估（页面加载只评可见组，D4）', () => {
  const manyDuplicates = () =>
    Array.from({ length: 25 }, (_, index) => ({
      duplicateId: `g${index + 1}`,
      suggestedKeepAssetIds: [`k${index + 1}`],
      assets: [{ id: `k${index + 1}` }, { id: `x${index + 1}` }],
    }));

  it('25 组时只提交前 3 组，一次请求，避免整库等待', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.getAssetDuplicates.mockResolvedValue(manyDuplicates());
    mocks.evaluateAiDedup.mockImplementation(({ aiDedupEvaluateDto }) =>
      evaluateResponse(
        (aiDedupEvaluateDto.duplicateIds as string[]).map((duplicateId) =>
          aiResult({ duplicateId, recommendedKeepAssetIds: [`k${duplicateId.slice(1)}`] }),
        ),
      ),
    );

    const data = await runLoad();

    expect(mocks.evaluateAiDedup).toHaveBeenCalledTimes(1);
    expect(mocks.evaluateAiDedup.mock.calls[0][0]).toEqual({
      aiDedupEvaluateDto: { duplicateIds: ['g1', 'g2', 'g3'] },
    });
    expect(data.aiEnabled).toBe(true);
    expect(Object.keys(data.aiResults)).toHaveLength(3);
    // Groups beyond the window remain on the official heuristic recommendation.
    expect(data.duplicates[20].suggestedKeepAssetIds).toEqual(['k21']);
  });

  it('URL 带 index 时以当前组为起点预取', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.getAssetDuplicates.mockResolvedValue(manyDuplicates());
    mocks.evaluateAiDedup.mockResolvedValue(evaluateResponse([]));

    await runLoad(10);

    expect(mocks.evaluateAiDedup.mock.calls[0][0]).toEqual({
      aiDedupEvaluateDto: { duplicateIds: ['g11', 'g12', 'g13'] },
    });
  });

  it('评估失败时全部组保持启发式预选，且不会重试', async () => {
    mocks.getAiDedupPrompt.mockResolvedValue(prompt());
    mocks.getAssetDuplicates.mockResolvedValue(manyDuplicates());
    mocks.evaluateAiDedup.mockRejectedValue(new Error('provider timeout'));

    const data = await runLoad();

    expect(mocks.evaluateAiDedup).toHaveBeenCalledTimes(1);
    expect(data.aiEnabled).toBe(false);
    expect(data.duplicates[0].suggestedKeepAssetIds).toEqual(['k1']);
    expect(data.duplicates[24].suggestedKeepAssetIds).toEqual(['k25']);
  });
});
