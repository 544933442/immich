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
    // [ai-dedup] Evaluate in batches: the backend caps each request at
    // maxGroupsPerRequest (default 20) and the DTO caps duplicateIds at 100, so
    // sending every group at once is either silently truncated (21+ groups) or
    // rejected outright (100+ groups), which used to disable the whole feature.
    const allIds = duplicates.map(({ duplicateId }) => duplicateId);
    const batchSize = 20;
    const allResults: AiDedupGroupResultDto[] = [];
    for (let start = 0; start < allIds.length; start += batchSize) {
      const batch = allIds.slice(start, start + batchSize);
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
