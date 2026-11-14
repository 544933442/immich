import {
  buildAiDedupGroupResultMap,
  buildAiDedupViewContext,
  formatScoreGap,
  isLowConfidence,
  isTrashReasonBadgeVisible,
  mergeAiKeepIds,
  resolveAiDeleteReason,
  type AiDedupAssetView,
  type AiDedupMergeableGroup,
} from '#lib/utils/ai-dedup.ts';
import {
  Decision,
  Source,
  type AiDedupAssetScoreDto,
  type AiDedupEvaluateResponseDto,
  type AiDedupGroupResultDto,
} from '@immich/sdk';

// QA 补充：v1.1 删除理由角标（B8~B11）与 D1 合并边界。
// 纯函数单测可在 node 模式运行，不受缺失的 Playwright Chromium 阻塞。

const FALLBACK = 'heuristic fallback (no AI reason)';

const makeScore = (overrides: Partial<AiDedupAssetScoreDto> = {}): AiDedupAssetScoreDto => ({
  assetId: 'a1',
  confidence: 0.8,
  decision: Decision.Trash,
  defects: ['motion_blur', 'noise'],
  deleteReason: '主体轻微脱焦，清晰度低于本组最佳的 9 分',
  index: 1,
  reason: '主体轻微脱焦',
  recommendedKeep: false,
  scoreGapToBest: 1.5,
  scores: { clarity: 7, quality: 7, composition: 7 },
  source: Source.Ai,
  weightedScore: 7.2,
  ...overrides,
});

const makeView = (overrides: Partial<AiDedupAssetView> = {}): AiDedupAssetView => ({
  score: makeScore(),
  bestScore: 8.7,
  degraded: false,
  needsManualReview: false,
  ...overrides,
});

const makeGroup = (overrides: Partial<AiDedupGroupResultDto> = {}): AiDedupGroupResultDto => ({
  degradeReason: null,
  degraded: false,
  duplicateId: 'g1',
  generatedAt: '2026-01-01T00:00:00.000Z',
  indexMap: {},
  model: 'gpt-4o',
  needsManualReview: false,
  promptVersion: 'ai-dedup-prompt-v1.0',
  recommendedKeepAssetIds: ['a2'],
  results: [makeScore(), makeScore({ assetId: 'a2', decision: Decision.Keep, recommendedKeep: true })],
  strategyApplied: false,
  summary: '',
  truncated: false,
  ...overrides,
});

const makeResponse = (results: AiDedupGroupResultDto[]): AiDedupEvaluateResponseDto => ({
  degradedCount: 0,
  quota: { limit: 200, used: 0 },
  results,
  truncatedCount: 0,
});

const makeDuplicates = (): AiDedupMergeableGroup[] => [
  { duplicateId: 'g1', suggestedKeepAssetIds: ['a1'], assets: [{ id: 'a1' }, { id: 'a2' }] },
  { duplicateId: 'g2', suggestedKeepAssetIds: ['b1'], assets: [{ id: 'b1' }, { id: 'b2' }] },
];

describe('B8 角标渲染条件：仅 decision=trash 且非降级/非人工复核', () => {
  const decisions = [Decision.Keep, Decision.Trash];
  const states = [false, true];

  for (const decision of decisions) {
    for (const degraded of states) {
      for (const needsManualReview of states) {
        const expected = decision === Decision.Trash && !degraded && !needsManualReview;
        it(`decision=${decision} degraded=${degraded} manual=${needsManualReview} => ${expected}`, () => {
          expect(
            isTrashReasonBadgeVisible(makeView({ degraded, needsManualReview, score: makeScore({ decision }) })),
          ).toBe(expected);
        });
      }
    }
  }

  it('view 缺失时不渲染', () => {
    expect(isTrashReasonBadgeVisible(undefined)).toBe(false);
    expect(isTrashReasonBadgeVisible(null)).toBe(false);
  });
});

describe('B11 降级/无理由一律走 fallback，绝不伪造 AI 理由', () => {
  it('降级组即使带 deleteReason 也返回 fallback', () => {
    expect(resolveAiDeleteReason(makeView({ degraded: true }), FALLBACK)).toBe(FALLBACK);
  });

  it('人工复核组返回 fallback', () => {
    expect(resolveAiDeleteReason(makeView({ needsManualReview: true }), FALLBACK)).toBe(FALLBACK);
  });

  it('deleteReason 为空白字符串时返回 fallback', () => {
    expect(resolveAiDeleteReason(makeView({ score: makeScore({ deleteReason: ' '.repeat(3) }) }), FALLBACK)).toBe(
      FALLBACK,
    );
  });

  it('deleteReason 缺失（旧缓存兼容）时返回 fallback', () => {
    expect(
      resolveAiDeleteReason(makeView({ score: makeScore({ deleteReason: undefined as unknown as string }) }), FALLBACK),
    ).toBe(FALLBACK);
  });

  it('view 缺失时返回 fallback', () => {
    expect(resolveAiDeleteReason(undefined, FALLBACK)).toBe(FALLBACK);
  });

  it('自信组原样返回模型理由且去除首尾空格', () => {
    expect(resolveAiDeleteReason(makeView({ score: makeScore({ deleteReason: '  主体脱焦  ' }) }), FALLBACK)).toBe(
      '主体脱焦',
    );
  });
});

describe('B10 低置信度提示与分差格式化边界', () => {
  it('阈值 0.5 的边界行为', () => {
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 0 }) }))).toBe(true);
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 0.4999 }) }))).toBe(true);
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 0.5 }) }))).toBe(false);
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 1 }) }))).toBe(false);
  });

  it('view 缺失时不标记低置信度', () => {
    expect(isLowConfidence(undefined)).toBe(false);
  });

  it('分差保留一位小数且永不为负', () => {
    expect(formatScoreGap(makeScore({ scoreGapToBest: 1.54 }))).toBe('1.5');
    expect(formatScoreGap(makeScore({ scoreGapToBest: 0 }))).toBe('0.0');
    expect(formatScoreGap(makeScore({ scoreGapToBest: -3 }))).toBe('0.0');
    expect(formatScoreGap(makeScore({ scoreGapToBest: 12.36 }))).toBe('12.4');
  });

  it('分差为 NaN / Infinity / 缺失时兜底 0.0', () => {
    expect(formatScoreGap(makeScore({ scoreGapToBest: NaN }))).toBe('0.0');
    expect(formatScoreGap(makeScore({ scoreGapToBest: Infinity }))).toBe('0.0');
    expect(formatScoreGap(undefined)).toBe('0.0');
  });
});

describe('B8/B10 理由卡数据：bestScore 与逐资产视图构建', () => {
  it('多组时 bestScore 按各自组内最高分计算，互不串组', () => {
    const g1 = makeGroup({ duplicateId: 'g1' });
    const g2 = makeGroup({
      duplicateId: 'g2',
      results: [
        makeScore({ assetId: 'c1', weightedScore: 9.9 }),
        makeScore({ assetId: 'c2', weightedScore: 6.1, decision: Decision.Keep, recommendedKeep: true }),
      ],
    });
    const context = buildAiDedupViewContext(buildAiDedupGroupResultMap(makeResponse([g1, g2])), true);

    expect(context.enabled).toBe(true);
    expect(context.byAssetId['a1'].bestScore).toBe(7.2);
    expect(context.byAssetId['c1'].bestScore).toBe(9.9);
    expect(context.byAssetId['c2'].score.defects).toEqual(['motion_blur', 'noise']);
    expect(context.byAssetId['c1'].score.deleteReason).toContain('清晰度');
  });

  it('关闭态返回空上下文（A1：无评分卡、无角标）', () => {
    const context = buildAiDedupViewContext(buildAiDedupGroupResultMap(makeResponse([makeGroup()])), false);

    expect(context).toEqual({ enabled: false, byAssetId: {} });
  });

  it('无结果时上下文为空但不抛错', () => {
    expect(buildAiDedupViewContext({}, true)).toEqual({ enabled: true, byAssetId: {} });
    expect(buildAiDedupGroupResultMap(null)).toEqual({});
  });
});

describe('D1 mergeAiKeepIds 覆盖条件的严格边界', () => {
  it('三个条件同时满足才覆盖（组合矩阵）', () => {
    const cases = [
      { degraded: false, needsManualReview: false, ids: ['a2'], overridden: true },
      { degraded: true, needsManualReview: false, ids: ['a2'], overridden: false },
      { degraded: false, needsManualReview: true, ids: ['a2'], overridden: false },
      { degraded: false, needsManualReview: false, ids: [], overridden: false },
      { degraded: true, needsManualReview: true, ids: [], overridden: false },
    ];
    for (const { degraded, needsManualReview, ids, overridden } of cases) {
      const merged = mergeAiKeepIds(
        makeDuplicates(),
        makeResponse([makeGroup({ degraded, needsManualReview, recommendedKeepAssetIds: ids })]),
      );
      expect(merged[0].suggestedKeepAssetIds).toEqual(overridden ? ['a2'] : ['a1']);
    }
  });

  it('未匹配到的组保持官方预选，且不影响其它组', () => {
    const merged = mergeAiKeepIds(makeDuplicates(), makeResponse([makeGroup({ duplicateId: 'g-unknown' })]));

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1']);
    expect(merged[1].suggestedKeepAssetIds).toEqual(['b1']);
  });

  it('保留多张时按成员过滤并维持 AI 返回顺序', () => {
    const merged = mergeAiKeepIds(
      makeDuplicates(),
      makeResponse([makeGroup({ recommendedKeepAssetIds: ['b2', 'a2', 'a1'] })]),
    );

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a2', 'a1']);
  });

  it('AI 推荐包含组内全部成员时只允许真实成员', () => {
    const merged = mergeAiKeepIds(
      makeDuplicates(),
      makeResponse([makeGroup({ recommendedKeepAssetIds: ['a1', 'a2', 'ghost'] })]),
    );

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1', 'a2']);
  });

  it('返回新数组且不修改入参对象（内存副本语义）', () => {
    const duplicates = makeDuplicates();
    const snapshot = structuredClone(duplicates);
    const merged = mergeAiKeepIds(duplicates, makeResponse([makeGroup()]));

    expect(merged).not.toBe(duplicates);
    expect(duplicates).toEqual(snapshot);
    expect(merged[0]).not.toBe(duplicates[0]);
    expect(merged[1]).toBe(duplicates[1]);
  });

  it('响应为 undefined / null / 空结果时返回原样副本', () => {
    const duplicates = makeDuplicates();
    for (const response of [undefined, null, makeResponse([])]) {
      const merged = mergeAiKeepIds(duplicates, response);
      expect(merged).toEqual(duplicates);
      expect(merged).not.toBe(duplicates);
    }
  });
});
