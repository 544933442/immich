// [ai-dedup]
// [ai-dedup]
// [ai-dedup]
// [ai-dedup]
import {
  buildAiDedupGroupResultMap,
  evaluateAiDedup,
  getAiDedupPrompt,
  mergeAiKeepIds,
  type AiDedupGroupResultDto,
  type AiDedupPromptDto,
} from '#lib/utils/ai-dedup.ts';
// [ai-dedup]
import { authenticate } from '#lib/utils/auth.ts';
import { getFormatter } from '#lib/utils/i18n.ts';
import { getAssetDuplicates } from '@immich/sdk';
// [ai-dedup]
import type { PageLoad } from './$types';

/** [ai-dedup] Number of groups evaluated on page load; the rest are evaluated on navigation. */
export const AI_DEDUP_INITIAL_GROUPS = 3;

export const load = (async ({ url }) => {
  await authenticate(url);
  const duplicates = await getAssetDuplicates();
  const $t = await getFormatter();

  // [ai-dedup] Query the AI state endpoint first; disabled => zero model calls (A1).
  let aiEnabled = false; // [ai-dedup]
  let aiPrompt: AiDedupPromptDto | null = null; // [ai-dedup]
  let aiResults: Record<string, AiDedupGroupResultDto> = {}; // [ai-dedup]
  try {
    // [ai-dedup]
    aiPrompt = await getAiDedupPrompt(); // [ai-dedup]
  } catch {
    // [ai-dedup]
    // [ai-dedup] An unavailable state endpoint is treated as "feature disabled".
  } // [ai-dedup]
  if (aiPrompt?.enabled) {
    // [ai-dedup] Evaluate ONLY the group currently on screen plus a small prefetch
    // window (technical design D4). A library can hold hundreds of duplicate groups;
    // evaluating all of them during page load made every reload wait for a full batch
    // of slow model calls. Other groups are evaluated lazily as the user navigates.
    const allIds = duplicates.map(({ duplicateId }) => duplicateId);
    const currentIndexParam = Number(url.searchParams.get('index') ?? '0');
    const startIndex = Number.isFinite(currentIndexParam) ? Math.max(0, Math.trunc(currentIndexParam)) : 0;
    const initialIds = allIds.slice(startIndex, startIndex + AI_DEDUP_INITIAL_GROUPS);
    const batchSize = 20;
    const allResults: AiDedupGroupResultDto[] = [];
    for (let start = 0; start < initialIds.length; start += batchSize) {
      const batch = initialIds.slice(start, start + batchSize);
      try {
        // [ai-dedup]
        const evaluated = await evaluateAiDedup({
          // [ai-dedup]
          aiDedupEvaluateDto: { duplicateIds: batch },
        });
        allResults.push(...evaluated.results);
      } catch {
        // [ai-dedup] A failed batch keeps the official heuristic result for those groups.
      }
    }

    if (allResults.length > 0) {
      // [ai-dedup]
      const combined = {
        degradedCount: allResults.filter((result) => result.degraded).length,
        quota: { limit: 0, used: 0 },
        results: allResults,
        truncatedCount: allResults.filter((result) => result.truncated).length,
      };
      const merged = mergeAiKeepIds(duplicates, combined);
      duplicates.splice(0, duplicates.length, ...merged);
      aiResults = buildAiDedupGroupResultMap(combined);
      aiEnabled = true;
    }
  }

  return {
    duplicates,
    meta: {
      title: $t('duplicates'),
    },
    aiEnabled, // [ai-dedup]
    aiPrompt, // [ai-dedup]
    aiResults, // [ai-dedup]
  };
}) satisfies PageLoad;
