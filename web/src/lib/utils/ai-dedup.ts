import {
  Decision,
  type AiDedupAssetScoreDto,
  type AiDedupEvaluateResponseDto,
  type AiDedupGroupResultDto,
} from '@immich/sdk';
import { getContext, setContext } from 'svelte';

/**
Additive, framework-facing helpers for the AI dedup module.

The server never rewrites `GET /api/duplicates`; this module owns the in-memory
overlay of `suggestedKeepAssetIds` (D1) and the read-only view context that lets
`DuplicatesCompareControl.svelte` consume AI scores without touching its
existing `$props()` destructuring (Svelte 5 forbids calling `$props()` twice).
*/

/** Minimal structural subset of a duplicate group; keeps the merger unit-testable. */
export interface AiDedupMergeableGroup {
  duplicateId: string;
  suggestedKeepAssetIds: string[];
  assets: { id: string }[];
}

export type AiDedupGroupResultMap = Record<string, AiDedupGroupResultDto>;

/** Everything a single photo card needs, pre-joined from its group result. */
export interface AiDedupAssetView {
  score: AiDedupAssetScoreDto;
  bestScore: number;
  degraded: boolean;
  needsManualReview: boolean;
}

export interface AiDedupViewContext {
  enabled: boolean;
  byAssetId: Record<string, AiDedupAssetView>;
}

const AI_DEDUP_CONTEXT_KEY = Symbol('ai-dedup-view');
const EMPTY_CONTEXT: AiDedupViewContext = { enabled: false, byAssetId: {} };

const LOW_CONFIDENCE_THRESHOLD = 0.5;

/**
Overlay AI keep recommendations onto a fresh in-memory copy of duplicate groups.

Only groups with a confident, non-degraded, non-empty AI recommendation are
overridden. Degraded / low-confidence / missing groups keep the official
heuristic result verbatim (A1, S4, S10). Hallucinated asset ids are dropped so
a malformed model response can never cause an unintended deletion (C1).
*/
export function mergeAiKeepIds<T extends AiDedupMergeableGroup>(
  duplicates: T[],
  evaluateResponse?: AiDedupEvaluateResponseDto | null,
): T[] {
  if (!evaluateResponse || evaluateResponse.results.length === 0) {
    return [...duplicates];
  }

  const byGroup = new Map<string, AiDedupGroupResultDto>();
  for (const result of evaluateResponse.results) {
    byGroup.set(result.duplicateId, result);
  }

  return duplicates.map((group) => {
    const result = byGroup.get(group.duplicateId);
    if (!result || result.degraded || result.needsManualReview || result.recommendedKeepAssetIds.length === 0) {
      return group;
    }

    const memberIds = new Set(group.assets.map(({ id }) => id));
    const keepIds = result.recommendedKeepAssetIds.filter((id) => memberIds.has(id));
    if (keepIds.length === 0) {
      return group;
    }

    return { ...group, suggestedKeepAssetIds: [...keepIds] };
  });
}

/** Index group results by duplicateId for O(1) lookup from the page. */
export function buildAiDedupGroupResultMap(response?: AiDedupEvaluateResponseDto | null): AiDedupGroupResultMap {
  const map: AiDedupGroupResultMap = {};
  for (const result of response?.results ?? []) {
    map[result.duplicateId] = result;
  }
  return map;
}

/** Flatten group results into an assetId-keyed view for the comparison cards. */
export function buildAiDedupViewContext(results: AiDedupGroupResultMap, enabled: boolean): AiDedupViewContext {
  if (!enabled) {
    return { enabled: false, byAssetId: {} };
  }

  const byAssetId: Record<string, AiDedupAssetView> = {};
  for (const result of Object.values(results)) {
    let bestScore = 0;
    for (const item of result.results) {
      if (item.weightedScore > bestScore) {
        bestScore = item.weightedScore;
      }
    }
    for (const score of result.results) {
      byAssetId[score.assetId] = {
        score,
        bestScore,
        degraded: result.degraded,
        needsManualReview: result.needsManualReview,
      };
    }
  }
  return { enabled: true, byAssetId };
}

/** Publish the AI view from the page; children read it with the hook below. */
export function provideAiDedupViewContext(value: AiDedupViewContext): void {
  setContext(AI_DEDUP_CONTEXT_KEY, value);
}

export function useAiDedupViewContext(): AiDedupViewContext {
  return getContext<AiDedupViewContext>(AI_DEDUP_CONTEXT_KEY) ?? EMPTY_CONTEXT;
}

/**
The trash reason badge is rendered only for a confident AI "trash" decision.
Degraded / manual-review groups fall back to the heuristic hint and never show
an AI reason (v1.1 6.2, B11).
*/
export function isTrashReasonBadgeVisible(view?: AiDedupAssetView | null): boolean {
  if (!view || view.degraded || view.needsManualReview) {
    return false;
  }
  return view.score.decision === Decision.Trash;
}

/** Always return a truthful reason; never fabricate an AI explanation. */
export function resolveAiDeleteReason(view: AiDedupAssetView | undefined, fallback: string): string {
  if (!view || view.degraded || view.needsManualReview) {
    return fallback;
  }
  return view.score.deleteReason?.trim() || fallback;
}

export function isLowConfidence(view: AiDedupAssetView | undefined): boolean {
  return !!view && view.score.confidence < LOW_CONFIDENCE_THRESHOLD;
}

/** Format a score gap as a one-decimal, never-negative value. */
export function formatScoreGap(score: AiDedupAssetScoreDto | undefined): string {
  const gap = score?.scoreGapToBest;
  return Number.isFinite(gap) ? Math.max(0, gap as number).toFixed(1) : '0.0';
}

// Re-export SDK symbols so existing files can add a single additive import line
// instead of a second `@immich/sdk` import (avoids import/no-duplicates).
export { evaluateAiDedup, getAiDedupPrompt } from '@immich/sdk';
export type { AiDedupGroupResultDto, AiDedupPromptDto } from '@immich/sdk';
