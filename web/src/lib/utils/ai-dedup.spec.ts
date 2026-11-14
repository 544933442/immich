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

const FALLBACK = 'Current recommendation is heuristic (file size and metadata); no AI reason available';

const makeScore = (overrides: Partial<AiDedupAssetScoreDto> = {}): AiDedupAssetScoreDto => ({
  assetId: 'a1',
  confidence: 0.8,
  decision: Decision.Trash,
  defects: ['motion_blur'],
  deleteReason: 'Subject slightly out of focus, clarity below the group best',
  index: 1,
  reason: 'Subject slightly out of focus',
  recommendedKeep: false,
  scoreGapToBest: 1.5,
  scores: { clarity: 7, quality: 7, composition: 7 },
  source: Source.Ai,
  weightedScore: 7.2,
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
  {
    duplicateId: 'g1',
    suggestedKeepAssetIds: ['a1'],
    assets: [{ id: 'a1' }, { id: 'a2' }],
  },
  {
    duplicateId: 'g2',
    suggestedKeepAssetIds: ['b1'],
    assets: [{ id: 'b1' }, { id: 'b2' }],
  },
];

const makeView = (overrides: Partial<AiDedupAssetView> = {}): AiDedupAssetView => ({
  score: makeScore(),
  bestScore: 8.7,
  degraded: false,
  needsManualReview: false,
  ...overrides,
});

describe('mergeAiKeepIds', () => {
  it('overrides only the group with a confident AI recommendation', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(duplicates, makeResponse([makeGroup()]));

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a2']);
    expect(merged[1].suggestedKeepAssetIds).toEqual(['b1']);
  });

  it('does not mutate the input array or its groups', () => {
    const duplicates = makeDuplicates();
    const original = structuredClone(duplicates);

    mergeAiKeepIds(duplicates, makeResponse([makeGroup()]));

    expect(duplicates).toEqual(original);
  });

  it('keeps the heuristic result for degraded groups', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(
      duplicates,
      makeResponse([makeGroup({ degraded: true, degradeReason: 'PROVIDER_ERROR' })]),
    );

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('keeps the heuristic result for low-confidence / manual-review groups', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(duplicates, makeResponse([makeGroup({ needsManualReview: true })]));

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('keeps the heuristic result when the recommended keep set is empty', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(duplicates, makeResponse([makeGroup({ recommendedKeepAssetIds: [] })]));

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('drops hallucinated asset ids and falls back when none remain valid', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(duplicates, makeResponse([makeGroup({ recommendedKeepAssetIds: ['not-in-group'] })]));

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a1']);
  });

  it('filters only hallucinated ids while keeping valid ones', () => {
    const duplicates = makeDuplicates();
    const merged = mergeAiKeepIds(
      duplicates,
      makeResponse([makeGroup({ recommendedKeepAssetIds: ['a2', 'not-in-group'] })]),
    );

    expect(merged[0].suggestedKeepAssetIds).toEqual(['a2']);
  });

  it('returns a copy unchanged when the response is missing or empty', () => {
    const duplicates = makeDuplicates();
    const fromNull = mergeAiKeepIds(duplicates, null);
    const fromEmpty = mergeAiKeepIds(duplicates, makeResponse([]));

    expect(fromNull).toEqual(duplicates);
    expect(fromNull).not.toBe(duplicates);
    expect(fromEmpty).toEqual(duplicates);
  });
});

describe('buildAiDedupGroupResultMap / buildAiDedupViewContext', () => {
  it('indexes group results by duplicateId', () => {
    const map = buildAiDedupGroupResultMap(makeResponse([makeGroup({ duplicateId: 'g9' })]));

    expect(Object.keys(map)).toEqual(['g9']);
  });

  it('returns an empty context when AI is disabled (A1)', () => {
    const context = buildAiDedupViewContext(buildAiDedupGroupResultMap(makeResponse([makeGroup()])), false);

    expect(context.enabled).toBe(false);
    expect(context.byAssetId).toEqual({});
  });

  it('flattens scores by assetId and computes the best score of each group', () => {
    const context = buildAiDedupViewContext(buildAiDedupGroupResultMap(makeResponse([makeGroup()])), true);

    expect(context.enabled).toBe(true);
    expect(context.byAssetId['a1'].bestScore).toBe(7.2);
    expect(context.byAssetId['a2'].score.decision).toBe(Decision.Keep);
  });
});

describe('isTrashReasonBadgeVisible', () => {
  it('is visible for a confident AI trash decision', () => {
    expect(isTrashReasonBadgeVisible(makeView())).toBe(true);
  });

  it('is hidden for keep decisions', () => {
    expect(isTrashReasonBadgeVisible(makeView({ score: makeScore({ decision: Decision.Keep }) }))).toBe(false);
  });

  it('is hidden for degraded groups (B11, no fabricated reason)', () => {
    expect(isTrashReasonBadgeVisible(makeView({ degraded: true }))).toBe(false);
  });

  it('is hidden for manual-review groups (S10)', () => {
    expect(isTrashReasonBadgeVisible(makeView({ needsManualReview: true }))).toBe(false);
  });

  it('is hidden when no view is available', () => {
    expect(isTrashReasonBadgeVisible(undefined)).toBe(false);
    expect(isTrashReasonBadgeVisible(null)).toBe(false);
  });
});

describe('resolveAiDeleteReason', () => {
  it('returns the model-derived reason verbatim', () => {
    expect(resolveAiDeleteReason(makeView(), FALLBACK)).toBe(
      'Subject slightly out of focus, clarity below the group best',
    );
  });

  it('uses the fallback when the reason is empty', () => {
    expect(resolveAiDeleteReason(makeView({ score: makeScore({ deleteReason: '' }) }), FALLBACK)).toBe(FALLBACK);
  });

  it('uses the fallback for degraded groups (no fabricated AI reason)', () => {
    expect(resolveAiDeleteReason(makeView({ degraded: true }), FALLBACK)).toBe(FALLBACK);
  });

  it('uses the fallback for manual-review groups', () => {
    expect(resolveAiDeleteReason(makeView({ needsManualReview: true }), FALLBACK)).toBe(FALLBACK);
  });

  it('uses the fallback when no view exists', () => {
    expect(resolveAiDeleteReason(undefined, FALLBACK)).toBe(FALLBACK);
  });
});

describe('isLowConfidence / formatScoreGap', () => {
  it('flags confidence below 0.5', () => {
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 0.42 }) }))).toBe(true);
    expect(isLowConfidence(makeView({ score: makeScore({ confidence: 0.5 }) }))).toBe(false);
  });

  it('formats a one-decimal, never-negative gap', () => {
    expect(formatScoreGap(makeScore({ scoreGapToBest: 1.54 }))).toBe('1.5');
    expect(formatScoreGap(makeScore({ scoreGapToBest: -2 }))).toBe('0.0');
    expect(formatScoreGap(undefined)).toBe('0.0');
  });
});
