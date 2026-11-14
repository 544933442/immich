<script lang="ts">
  import { Route } from '#lib/route.ts';
  import { handleError } from '#lib/utils/handle-error.ts';
  import { evaluateAiDedup, type AiDedupGroupResultDto, type AiDedupPromptDto } from '@immich/sdk';
  import { Button, modalManager, toastManager } from '@immich/ui';
  import { mdiRefresh, mdiTextBoxOutline, mdiTrashCanOutline } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { goto } from '$app/navigation';

  /**
  Additive recommendation strip above the duplicate comparison cards.
  Renders nothing when the feature is disabled (A1). All actions are read-only
  or re-evaluation only; deletion still goes through resolveDuplicates.
  */
  interface Props {
    aiEnabled: boolean;
    aiPrompt: AiDedupPromptDto | null;
    aiResult?: AiDedupGroupResultDto;
    onReevaluate?: (result: AiDedupGroupResultDto) => void;
  }

  let { aiEnabled, aiPrompt, aiResult, onReevaluate }: Props = $props();

  let localResult = $derived<AiDedupGroupResultDto | undefined>(aiResult);
  let busy = $state(false);
  // [ai-dedup] Token guard: the bar is destroyed when the user switches groups ({#key}),
  // but the in-flight force-evaluation promise still resolves later. Every stale
  // response (and its onReevaluate write-back into the page state) is discarded.
  let reevaluateToken = 0;

  onDestroy(() => {
    reevaluateToken++;
  });

  const confidence = $derived.by(() => {
    const scores = localResult?.results ?? [];
    if (scores.length === 0) {
      return '0.00';
    }

    let total = 0;
    for (const item of scores) {
      total += item.confidence;
    }
    return (total / scores.length).toFixed(2);
  });

  const viewPrompt = async () => {
    await modalManager.showDialog({
      title: $t('ai_dedup_prompt_template_readonly'),
      prompt: aiPrompt?.promptTemplate ?? '',
      confirmText: $t('confirm'),
    });
  };

  const reevaluate = async () => {
    if (!localResult || busy) {
      return;
    }

    busy = true;
    const token = ++reevaluateToken;
    try {
      const response = await evaluateAiDedup({
        aiDedupEvaluateDto: { duplicateIds: [localResult.duplicateId], force: true },
      });
      if (token !== reevaluateToken) {
        // Stale response for a group the user has already navigated away from.
        return;
      }
      const [result] = response.results;
      if (result) {
        localResult = result;
        onReevaluate?.(result);
      }
      toastManager.primary($t('ai_dedup_reevaluate_done'));
    } catch (error) {
      if (token === reevaluateToken) {
        handleError(error, $t('ai_dedup_reevaluate_failed'));
      }
    } finally {
      if (token === reevaluateToken) {
        busy = false;
      }
    }
  };

  const goToTrash = () => void goto(Route.trash());
</script>

{#if aiEnabled}
  <div
    class="mx-auto mb-4 max-w-5xl rounded-2xl border border-[#e6ecf5] bg-linear-to-br from-[#f8faff] to-[#eef0ff] p-3 text-[#1e293b] shadow-[0_8px_24px_rgba(60,80,130,0.08)]"
    data-ai-dedup-recommendation-bar
  >
    <div class="flex flex-wrap items-center justify-between gap-2">
      <div class="flex flex-wrap items-center gap-2 text-[12px]">
        <span class="grid size-6 place-items-center rounded-lg bg-[#eef0ff] text-[13px] font-bold text-[#6366f1]">
          &#10022;
        </span>
        <strong class="text-[13px]">{$t('ai_dedup_recommendation_bar')}</strong>
        {#if localResult}
          <span class="rounded-full bg-white px-2 py-0.5 text-[#52627a]">{localResult.model}</span>
        {/if}
        {#if aiPrompt}
          <span class="rounded-full bg-white px-2 py-0.5 text-[#52627a]">{aiPrompt.strategySummary}</span>
          <span class="rounded-full bg-white px-2 py-0.5 text-[#8a98ad]">{aiPrompt.version}</span>
        {/if}
        <span class="rounded-full bg-[#e3f8f6] px-2 py-0.5 text-[#0ea5a4]">
          {$t('ai_dedup_confidence', { values: { value: confidence } })}
        </span>
      </div>

      <div class="flex flex-wrap gap-1">
        <Button size="small" variant="ghost" color="secondary" leadingIcon={mdiTextBoxOutline} onclick={viewPrompt}>
          {$t('ai_dedup_view_prompt')}
        </Button>
        <Button
          size="small"
          variant="ghost"
          color="secondary"
          leadingIcon={mdiRefresh}
          disabled={busy || !localResult}
          onclick={reevaluate}
        >
          {$t('ai_dedup_reevaluate')}
        </Button>
        <Button size="small" variant="ghost" color="secondary" leadingIcon={mdiTrashCanOutline} onclick={goToTrash}>
          {$t('ai_dedup_go_to_trash')}
        </Button>
      </div>
    </div>

    {#if !localResult}
      <p class="mt-2 text-[11px] text-[#8a98ad]">{$t('ai_dedup_heuristic_fallback')}</p>
    {:else if localResult.degraded}
      <p class="mt-2 text-[11px] text-[#b45309]">
        {$t('ai_dedup_degraded_group')}{localResult.degradeReason ? ` · ${localResult.degradeReason}` : ''}
      </p>
    {:else if localResult.needsManualReview}
      <p class="mt-2 text-[11px] text-[#b45309]">{$t('ai_dedup_manual_review')}</p>
    {/if}

    {#if localResult?.truncated}
      <p class="mt-1 text-[11px] text-[#8a98ad]">{$t('ai_dedup_too_many_images')}</p>
    {/if}

    {#if aiPrompt}
      <p class="mt-1 text-[11px] text-[#8a98ad]">{$t('ai_dedup_trash_days_notice')}</p>
    {/if}
  </div>
{/if}
