import type { AssetResponseDto } from 'src/dtos/asset-response.dto.js';
import { suggestDuplicateKeepAssetIds } from 'src/utils/duplicate.js';
import {
  AI_DEDUP_DEGRADED_REASON_FALLBACK,
  AI_DEDUP_DEFECT_ENUM,
  AI_DEDUP_PROMPT_VERSION,
} from 'src/ai-dedup/constants.js';
import {
  AiDedupErrorCode,
  AiDedupModelResponseSchema,
  type AiDedupAssetScore,
  type AiDedupGroupResult,
  type AiDedupIndexMap,
  type AiDedupScores,
} from 'src/ai-dedup/dto.js';

const round1 = (value: number): number => Math.round(value * 10) / 10;

/** Truncate by Unicode code point so Chinese reasons stay within 40 characters. */
export const truncateReason = (text: string, max = 40): string => [...text].slice(0, max).join('');

const DIMENSION_LABELS: Record<keyof AiDedupScores, string> = {
  clarity: '清晰度',
  quality: '画质',
  composition: '构图',
};

const DEFECT_LABELS: Record<string, string> = {
  eyes_closed: '闭眼',
  overexposed: '高光过曝',
  underexposed: '欠曝',
  cropped_subject: '主体被裁切',
  cropped: '边缘裁切',
  blurry: '画面模糊',
  motion_blur: '运动拖影',
  occluded: '有遮挡',
  noise: '噪点偏多',
  red_eye: '红眼',
  glare: '玻璃反光',
  tilted: '地平线倾斜',
  other: '可见缺陷',
};

const VAGUE_REASON =
  /这张更好|这张更差|更优|更好|略好|评分较低|分数较低|不推荐|建议删除|best|better|worse|^[\s。，；;,.!?]*$/iu;

/** A reason with no concrete dimension/defect information must not be reused as a delete reason. */
export function isVagueReason(reason: string): boolean {
  const text = reason.trim();
  return [...text].length < 4 || VAGUE_REASON.test(text);
}

export interface AiDedupDegradedInput {
  duplicateId: string;
  assets: AssetResponseDto[];
  model?: string;
  promptVersion?: string;
  generatedAt?: string;
}

export interface AiDedupParserContext extends AiDedupDegradedInput {
  model: string;
  promptVersion: string;
  /** Asset ids actually sent to the model, in shuffled 1..N order. */
  scoredAssetIds: string[];
  /** Members not sent (S8) — appended as heuristic rows, never silently dropped. */
  unscoredAssetIds?: string[];
  indexMap: AiDedupIndexMap;
  keepCount: number;
  lowConfidenceThreshold: number;
  lowConfidenceStrict: boolean;
  strategyApplied: boolean;
  truncated?: boolean;
}

export type AiDedupParseOutcome =
  | { ok: true; result: AiDedupGroupResult }
  | { ok: false; code: AiDedupErrorCode };

type Rankable = {
  weightedScore: number;
  scores: AiDedupScores;
  defects: string[];
  index: number;
};

/**
Server-side second ruling (technical design §3.6.3). The model's ordering is never trusted:
weightedScore DESC -> clarity -> quality -> composition -> fewer defects -> smaller index.
*/
export function rerank<T extends Rankable>(items: T[]): T[] {
  return [...items].sort(
    (a, b) =>
      b.weightedScore - a.weightedScore ||
      b.scores.clarity - a.scores.clarity ||
      b.scores.quality - a.scores.quality ||
      b.scores.composition - a.scores.composition ||
      a.defects.length - b.defects.length ||
      a.index - b.index,
  );
}

/** Unknown defects are mapped to `other` rather than failing the group. */
export function normalizeDefects(defects: string[]): string[] {
  const known = new Set<string>(AI_DEDUP_DEFECT_ENUM);
  const normalized = defects.map((defect) => {
    const value = defect.trim().toLowerCase();
    return known.has(value) ? value : 'other';
  });
  return [...new Set<string>(normalized)];
}

/** Minimal shape needed to derive a delete reason (shared by ranked model rows and final scores). */
export type AiDedupDeleteReasonSource = Pick<
  AiDedupAssetScore,
  'scores' | 'weightedScore' | 'reason' | 'defects'
>;

/**
v1.1: derive a <=40 char Chinese delete reason that names the concrete disadvantage
relative to the best photo in the group (03-design-overview.md §6.2 / §6.5).
Never produces vague wording such as "评分较低" / "这张更差".
*/
export function deriveDeleteReason(
  item: AiDedupDeleteReasonSource,
  best: AiDedupDeleteReasonSource,
  strategyApplied: boolean,
): string {
  const dimensions: (keyof AiDedupScores)[] = ['clarity', 'quality', 'composition'];
  let weakest: keyof AiDedupScores = 'clarity';
  let worstDiff = -Infinity;
  for (const dimension of dimensions) {
    const diff = best.scores[dimension] - item.scores[dimension];
    if (!(diff > worstDiff)) {
      continue;
    }

    worstDiff = diff;
    weakest = dimension;
  }

  const gap = round1(Math.max(0, best.weightedScore - item.weightedScore));
  const detail = `${DIMENSION_LABELS[weakest]}低于本组最佳 ${round1(Math.max(0, worstDiff))} 分`;
  const base = isVagueReason(item.reason) ? '' : item.reason.replace(/[。；;，,、\s]+$/u, '');
  const defect = item.defects.find((value) => value !== 'other');
  const defectText = defect ? (DEFECT_LABELS[defect] ?? defect) : '';

  let text = base ? `${base}，${detail}` : defectText ? `${defectText}，${detail}` : detail;
  if (gap > 0 && [...text].length < 30) {
    text += `（总分低 ${gap} 分）`;
  }
  // Keep delete reasons consistent with the active strategy (R-31).
  if (strategyApplied && !/策略|降权/u.test(text)) {
    text = `按当前策略降权：${text}`;
  }

  return truncateReason(text || '相对本组最佳照片略逊，建议人工确认');
}

/** Extract the first `{ ... }` block; tolerates Markdown fences and surrounding prose. */
export function extractJson(text: string): string {
  const start = text.indexOf('{');
  const end = text.lastIndexOf('}');
  if (start === -1 || end <= start) {
    throw new Error('No JSON object found in model response');
  }
  return text.slice(start, end + 1);
}

const makePlaceholder = (assetId: string, index: number): AiDedupAssetScore => ({
  assetId,
  index,
  scores: { clarity: 0, quality: 0, composition: 0 },
  weightedScore: 0,
  confidence: 0,
  reason: '',
  defects: [],
  recommendedKeep: false,
  decision: 'trash',
  deleteReason: AI_DEDUP_DEGRADED_REASON_FALLBACK,
  scoreGapToBest: 0,
  source: 'heuristic',
});

const invalid = (): AiDedupParseOutcome => ({ ok: false, code: AiDedupErrorCode.InvalidResponse });

/**
JSON cleanup -> zod safeParse -> business validation -> server re-ranking -> v1.1 derived
fields. Any failure returns a coded degradation (never throws, never yields partial data).
*/
export function parseAndValidate(content: string, ctx: AiDedupParserContext): AiDedupParseOutcome {
  let raw: unknown;
  try {
    raw = JSON.parse(extractJson(content)) as unknown;
  } catch {
    return invalid();
  }

  const safe = AiDedupModelResponseSchema.safeParse(raw);
  if (!safe.success) {
    return invalid();
  }

  const model = safe.data;
  const count = ctx.scoredAssetIds.length;
  if (count === 0 || model.results.length !== count) {
    return invalid();
  }

  const indices = model.results.map((item) => item.index);
  if (new Set(indices).size !== count || indices.some((index) => index < 1 || index > count)) {
    return invalid();
  }

  const keepCount = Math.min(Math.max(1, ctx.keepCount), count);
  const keepIndices = model.recommendedKeepIndices;
  if (
    keepIndices.length !== keepCount ||
    new Set(keepIndices).size !== keepCount ||
    keepIndices.some((index) => index < 1 || index > count)
  ) {
    return invalid();
  }

  // The server recomputes weightedScore; a >0.15 discrepancy is corrected, not rejected.
  const normalized = model.results.map((item) => {
    const computed = round1(
      item.scores.clarity * 0.35 + item.scores.quality * 0.35 + item.scores.composition * 0.3,
    );
    return {
      ...item,
      weightedScore: Math.abs(computed - item.weightedScore) > 0.15 ? computed : item.weightedScore,
      defects: normalizeDefects(item.defects),
    };
  });

  const ranked = rerank(normalized);
  const best = ranked[0];
  const rankedKeepIndices = new Set(ranked.slice(0, keepCount).map((item) => item.index));
  if (ranked.some((item) => !ctx.indexMap[String(item.index)])) {
    return invalid();
  }

  let results: AiDedupAssetScore[] = ranked.map((item) => ({
    assetId: ctx.indexMap[String(item.index)],
    index: item.index,
    scores: item.scores,
    weightedScore: item.weightedScore,
    confidence: item.confidence,
    reason: truncateReason(item.reason),
    defects: item.defects,
    recommendedKeep: rankedKeepIndices.has(item.index),
    decision: rankedKeepIndices.has(item.index) ? 'keep' : 'trash',
    deleteReason: '',
    scoreGapToBest: round1(Math.max(0, best.weightedScore - item.weightedScore)),
    source: 'ai',
  }));

  // S8: members beyond maxImagesPerGroup are appended as heuristic rows, not dropped.
  for (const assetId of ctx.unscoredAssetIds ?? []) {
    results.push(makePlaceholder(assetId, results.length + 1));
  }

  // v1.1 derived fields: decision / deleteReason / scoreGapToBest.
  results = results.map((item) => ({
    ...item,
    decision: item.recommendedKeep ? 'keep' : 'trash',
    scoreGapToBest: round1(Math.max(0, best.weightedScore - item.weightedScore)),
    deleteReason:
      item.recommendedKeep || item.source === 'heuristic'
        ? item.source === 'heuristic'
          ? AI_DEDUP_DEGRADED_REASON_FALLBACK
          : ''
        : deriveDeleteReason(item, best, ctx.strategyApplied),
  }));

  const aiConfidences = results.filter((item) => item.source === 'ai').map((item) => item.confidence);
  const lowestConfidence = Math.min(...aiConfidences, 1);
  const needsManualReview = ctx.lowConfidenceStrict && lowestConfidence < ctx.lowConfidenceThreshold;
  const keepAssetIds = results.filter((item) => item.recommendedKeep).map((item) => item.assetId);

  return {
    ok: true,
    result: {
      duplicateId: ctx.duplicateId,
      recommendedKeepAssetIds: needsManualReview ? [] : keepAssetIds,
      results,
      summary: truncateReason(model.summary, 60),
      strategyApplied: ctx.strategyApplied,
      promptVersion: ctx.promptVersion,
      model: ctx.model,
      generatedAt: ctx.generatedAt ?? new Date().toISOString(),
      degraded: false,
      degradeReason: needsManualReview ? AiDedupErrorCode.LowConfidence : null,
      needsManualReview,
      truncated: ctx.truncated ?? false,
      indexMap: ctx.indexMap,
    },
  };
}

/**
The single degradation entry point. Uses `suggestDuplicateKeepAssetIds` as a read-only pure
function (src/utils/duplicate.ts is never modified) so the result is still explainable,
while `recommendedKeepAssetIds` stays empty and `degraded=true` guarantees the frontend does
NOT overwrite `suggestedKeepAssetIds` and never deletes based on an incomplete AI result.
*/
export function buildDegradedResult(
  input: AiDedupDegradedInput,
  reason: AiDedupErrorCode,
): AiDedupGroupResult {
  const heuristicKeepIds = new Set<string>(suggestDuplicateKeepAssetIds(input.assets));
  const results: AiDedupAssetScore[] = input.assets.map((asset, position) => {
    const keep = heuristicKeepIds.has(asset.id);
    return {
      assetId: asset.id,
      index: position + 1,
      scores: { clarity: 0, quality: 0, composition: 0 },
      weightedScore: 0,
      confidence: 0,
      reason: '',
      defects: [],
      recommendedKeep: keep,
      decision: keep ? 'keep' : 'trash',
      deleteReason: AI_DEDUP_DEGRADED_REASON_FALLBACK,
      scoreGapToBest: 0,
      source: 'heuristic',
    };
  });

  return {
    duplicateId: input.duplicateId,
    recommendedKeepAssetIds: [],
    results,
    summary: 'AI 不可用，已回退启发式推荐（按文件体积与元数据）',
    strategyApplied: false,
    promptVersion: input.promptVersion ?? AI_DEDUP_PROMPT_VERSION,
    model: input.model ?? '',
    generatedAt: input.generatedAt ?? new Date().toISOString(),
    degraded: true,
    degradeReason: reason,
    needsManualReview: false,
    truncated: false,
    indexMap: {},
  };
}
