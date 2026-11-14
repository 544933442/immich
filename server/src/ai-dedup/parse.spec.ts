import { describe, expect, it } from 'vitest';
import type { AssetResponseDto } from 'src/dtos/asset-response.dto.js';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';
import {
  buildDegradedResult,
  deriveDeleteReason,
  extractJson,
  isVagueReason,
  normalizeDefects,
  parseAndValidate,
  rerank,
  type AiDedupParserContext,
} from 'src/ai-dedup/parse.js';

/** Valid UUID v4 strings so results also satisfy AiDedupGroupResultSchema at runtime. */
const assetId = (n: number): string => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const makeAsset = (id: string, fileSizeInByte: number): AssetResponseDto =>
  ({ id, exifInfo: { fileSizeInByte } }) as unknown as AssetResponseDto;

const context = (overrides: Partial<AiDedupParserContext> = {}): AiDedupParserContext => ({
  duplicateId: assetId(99),
  assets: [],
  model: 'gpt-4o-mini',
  promptVersion: 'ai-dedup-prompt-v1.0',
  scoredAssetIds: [assetId(1), assetId(2)],
  indexMap: { '1': assetId(1), '2': assetId(2) },
  keepCount: 1,
  lowConfidenceThreshold: 0.5,
  lowConfidenceStrict: false,
  strategyApplied: false,
  ...overrides,
});

interface ModelRow {
  index: number;
  scores: { clarity: number; quality: number; composition: number };
  weightedScore: number;
  confidence: number;
  reason: string;
  defects: string[];
}

const row = (index: number, score: number, confidence = 0.9, reason = '主体合焦，细节清晰'): ModelRow => ({
  index,
  scores: { clarity: score, quality: score, composition: score },
  // clarity*0.35 + quality*0.35 + composition*0.30 === score
  weightedScore: score,
  confidence,
  reason,
  defects: [],
});

const response = (rows: ModelRow[], keepIndices: number[]): string =>
  JSON.stringify({
    version: 'ai-dedup-prompt-v1.0',
    strategyApplied: false,
    results: rows,
    recommendedKeepIndices: keepIndices,
    summary: '清晰度更高者保留',
  });

describe('rerank', () => {
  it('orders by weightedScore then clarity, quality, composition, fewer defects, lower index', () => {
    const items = [
      { index: 1, weightedScore: 8, scores: { clarity: 8, quality: 8, composition: 8 }, defects: ['blurry'] },
      { index: 2, weightedScore: 8, scores: { clarity: 8, quality: 8, composition: 8 }, defects: [] },
      { index: 3, weightedScore: 9, scores: { clarity: 9, quality: 9, composition: 9 }, defects: [] },
      { index: 4, weightedScore: 8, scores: { clarity: 8, quality: 7, composition: 8 }, defects: [] },
    ];
    // 3 wins on total; among the 8-point ties, quality 8 beats quality 7, and among the
    // remaining two the one with fewer defects wins before the index tie-break.
    expect(rerank(items).map((item) => item.index)).toEqual([3, 2, 1, 4]);
  });

  it('does not mutate the input array', () => {
    const items = [row(1, 5), row(2, 9)];
    rerank(items);
    expect(items.map((item) => item.index)).toEqual([1, 2]);
  });
});

describe('normalizeDefects / isVagueReason', () => {
  it('maps unknown defects to other and de-duplicates', () => {
    expect(normalizeDefects(['BLURRY', 'made-up', 'blurry', 'eyes_closed'])).toEqual([
      'blurry',
      'other',
      'eyes_closed',
    ]);
  });

  it('rejects empty and vague reasons', () => {
    expect(isVagueReason('这张更差')).toBe(true);
    expect(isVagueReason('评分较低')).toBe(true);
    expect(isVagueReason('  ')).toBe(true);
    expect(isVagueReason('主体脱焦，清晰度低于本组最佳')).toBe(false);
  });
});

describe('deriveDeleteReason (v1.1)', () => {
  it('names the weakest dimension relative to the best photo', () => {
    const best = row(1, 9);
    const worse = row(2, 5, 0.9, '这张更差');
    const reason = deriveDeleteReason(worse, best, false);
    expect(reason).toContain('低于本组最佳');
    expect(reason).not.toContain('这张更差');
    expect([...reason].length).toBeLessThanOrEqual(40);
  });

  it('marks an active strategy and still stays <= 40 characters', () => {
    const best = row(1, 9);
    const worse = row(2, 4);
    const reason = deriveDeleteReason(worse, best, true);
    expect(reason).toContain('按当前策略降权');
    expect([...reason].length).toBeLessThanOrEqual(40);
  });
});

describe('extractJson', () => {
  it('extracts the first JSON object from a fenced / chatty response', () => {
    const text = '好的，结果如下：\n```json\n{"a":1,"b":{"c":2}}\n```\n以上。';
    expect(extractJson(text)).toBe('{"a":1,"b":{"c":2}}');
  });

  it('throws when no object is present', () => {
    expect(() => extractJson('no json here')).toThrow();
  });
});

describe('parseAndValidate', () => {
  it('re-ranks server-side and derives decision / deleteReason / scoreGapToBest', () => {
    // Deliberately send the worse photo first and a wrong keep index: the server must not
    // trust the model's ordering.
    const outcome = parseAndValidate(response([row(1, 4), row(2, 9)], [1]), context());
    expect(outcome.ok).toBe(true);
    if (!outcome.ok) {
      return;
    }

    const result = outcome.result;
    expect(result.degraded).toBe(false);
    expect(result.recommendedKeepAssetIds).toEqual([assetId(2)]);
    expect(result.results.map((item) => item.assetId)).toEqual([assetId(2), assetId(1)]);
    expect(result.results[0].decision).toBe('keep');
    expect(result.results[0].deleteReason).toBe('');
    expect(result.results[1].decision).toBe('trash');
    expect(result.results[1].deleteReason).toContain('低于本组最佳');
    expect(result.results[1].scoreGapToBest).toBe(5);
    expect(result.results.every((item) => item.source === 'ai')).toBe(true);
    expect(result.indexMap).toEqual({ '1': assetId(1), '2': assetId(2) });
  });

  it('degrades on invalid JSON or a schema violation', () => {
    expect(parseAndValidate('not json', context())).toEqual({ ok: false, code: AiDedupErrorCode.InvalidResponse });
    expect(parseAndValidate(response([row(1, 5)], [1]), context())).toEqual({
      ok: false,
      code: AiDedupErrorCode.InvalidResponse,
    });
  });

  it('rejects duplicate / out-of-range indices and a wrong keep-index count', () => {
    const duplicated = response([row(1, 5), row(1, 7)], [1]);
    expect(parseAndValidate(duplicated, context())).toEqual({
      ok: false,
      code: AiDedupErrorCode.InvalidResponse,
    });
    expect(parseAndValidate(response([row(1, 5), row(2, 7)], [1, 2, 3]), context())).toEqual({
      ok: false,
      code: AiDedupErrorCode.InvalidResponse,
    });
  });

  it('applies the conservative low-confidence policy when enabled', () => {
    const outcome = parseAndValidate(
      response([row(1, 4, 0.2), row(2, 9, 0.2)], [2]),
      context({ lowConfidenceStrict: true, lowConfidenceThreshold: 0.5 }),
    );
    expect(outcome.ok).toBe(true);
    if (!outcome.ok) {
      return;
    }
    expect(outcome.result.needsManualReview).toBe(true);
    expect(outcome.result.recommendedKeepAssetIds).toEqual([]);
    expect(outcome.result.degradeReason).toBe(AiDedupErrorCode.LowConfidence);
    // Scores are still returned for display; only the pre-selection is withheld.
    expect(outcome.result.results).toHaveLength(2);
  });

  it('appends truncated members as heuristic rows instead of dropping them', () => {
    const outcome = parseAndValidate(
      response([row(1, 4), row(2, 9)], [2]),
      context({ unscoredAssetIds: [assetId(3)], truncated: true }),
    );
    expect(outcome.ok).toBe(true);
    if (!outcome.ok) {
      return;
    }
    expect(outcome.result.truncated).toBe(true);
    expect(outcome.result.results).toHaveLength(3);
    expect(outcome.result.results[2]).toMatchObject({
      assetId: assetId(3),
      source: 'heuristic',
      decision: 'trash',
    });
  });
});

describe('buildDegradedResult', () => {
  it('uses the read-only heuristic but never exposes a recommended keep set', () => {
    const assets = [makeAsset(assetId(1), 100), makeAsset(assetId(2), 200)];
    const result = buildDegradedResult(
      { duplicateId: assetId(99), assets },
      AiDedupErrorCode.ProviderError,
    );

    expect(result.degraded).toBe(true);
    expect(result.degradeReason).toBe(AiDedupErrorCode.ProviderError);
    expect(result.recommendedKeepAssetIds).toEqual([]);
    expect(result.results).toHaveLength(2);
    expect(result.results.find((item) => item.assetId === assetId(2))?.decision).toBe('keep');
    expect(result.results.find((item) => item.assetId === assetId(1))?.decision).toBe('trash');
    expect(result.results.every((item) => item.source === 'heuristic')).toBe(true);
  });
});
