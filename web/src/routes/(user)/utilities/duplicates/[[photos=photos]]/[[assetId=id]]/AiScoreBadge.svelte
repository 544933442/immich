<script lang="ts">
  import type { AiDedupAssetScoreDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';

  /** Compact, read-only score card for a single duplicate photo. */
  interface Props {
    score: AiDedupAssetScoreDto;
    recommendedKeep?: boolean;
  }

  let { score, recommendedKeep = false }: Props = $props();

  const asPercent = (value: number): number => Math.max(0, Math.min(100, (value / 10) * 100));
  const oneDecimal = (value: number): string => (Number.isFinite(value) ? value.toFixed(1) : '0.0');

  const dimensions = $derived([
    { label: $t('ai_dedup_score_clarity'), value: score.scores.clarity },
    { label: $t('ai_dedup_score_quality'), value: score.scores.quality },
    { label: $t('ai_dedup_score_composition'), value: score.scores.composition },
  ]);
</script>

<div
  class="mt-1 w-full rounded-xl border border-[#e6ecf5] bg-linear-to-br from-[#f8faff] to-[#eef0ff] p-2.5 text-[#1e293b] shadow-[0_6px_18px_rgba(60,80,130,0.08)]"
  data-ai-dedup-score-card
>
  <div class="flex items-baseline justify-between">
    <div class="text-lg leading-none font-bold">
      {oneDecimal(score.weightedScore)}<span class="ms-1 text-[11px] font-medium text-[#8a98ad]">/10</span>
    </div>
    <span class="text-[11px] text-[#52627a]">
      {$t('ai_dedup_confidence', { values: { value: oneDecimal(score.confidence) } })}
    </span>
  </div>

  {#if recommendedKeep}
    <div class="mt-1 inline-flex rounded-md bg-[#e3f8f6] px-1.5 py-0.5 text-[10px] font-medium text-[#0ea5a4]">
      {$t('ai_dedup_recommended_keep')}
    </div>
  {/if}

  <div class="mt-2 grid gap-1">
    {#each dimensions as dimension (dimension.label)}
      <div class="grid grid-cols-[46px_1fr_18px] items-center gap-1.5 text-[10px] text-[#52627a]">
        <span>{dimension.label}</span>
        <div class="h-1 overflow-hidden rounded-full bg-[#edf1f8]">
          <div
            class="h-full rounded-full bg-linear-to-r from-[#8b93ff] to-[#6366f1]"
            style="width: {asPercent(dimension.value)}%"
          ></div>
        </div>
        <b class="text-right font-semibold text-[#52627a]">{dimension.value}</b>
      </div>
    {/each}
  </div>

  {#if score.reason}
    <p class="mt-2 line-clamp-2 text-[11px] leading-snug text-[#52627a]">「{score.reason}」</p>
  {/if}

  {#if score.defects.length > 0}
    <div class="mt-1.5 flex flex-wrap gap-1">
      {#each score.defects as defect (defect)}
        <span class="rounded-md bg-[#fff0e9] px-1.5 py-0.5 text-[10px] text-[#e8734a]">{defect}</span>
      {/each}
    </div>
  {/if}
</div>
