<script lang="ts">
  import {
    formatScoreGap,
    isLowConfidence,
    isTrashReasonBadgeVisible,
    resolveAiDeleteReason,
    type AiDedupAssetView,
  } from '#lib/utils/ai-dedup.ts';
  import { t } from 'svelte-i18n';

  /**
  v1.1 delete-reason badge: a ~20px circular info marker anchored to the
  top-right corner of its AI score-card column with plain CSS. Desktop hover or
  keyboard focus, touch click, mouseleave, blur, Escape and an in-card close
  button all collapse the popover. The popover is clamped to the viewport when
  it opens so it never covers the existing comparison-card action buttons.

  No window listeners, observers or DOM queries are registered: the marker is
  positioned by CSS only, which keeps this component fully independent of the
  official card markup (zero changes to existing function bodies).
  */
  interface Props {
    view: AiDedupAssetView;
  }

  let { view }: Props = $props();

  const id = $props.id();
  const tipId = `ai-dedup-tip-${id}`;
  const POPOVER_WIDTH = 268;
  const POPOVER_HEIGHT = 220;
  const VIEWPORT_MARGIN = 8;

  let open = $state(false);
  let badgeElement: HTMLButtonElement | undefined = $state();
  let tipElement: HTMLDivElement | undefined = $state();
  let position = $state({ top: 0, left: 0 });

  const visible = $derived(isTrashReasonBadgeVisible(view));
  const reason = $derived(resolveAiDeleteReason(view, $t('ai_dedup_delete_reason_fallback')));
  const lowConfidence = $derived(isLowConfidence(view));
  const gap = $derived(formatScoreGap(view?.score));

  /** Clamp the popover beside the marker; computed once, when it opens. */
  const updatePosition = () => {
    if (!badgeElement) {
      return;
    }

    const rect = badgeElement.getBoundingClientRect();
    let left = rect.right + VIEWPORT_MARGIN;
    if (left + POPOVER_WIDTH > window.innerWidth - VIEWPORT_MARGIN) {
      left = rect.left - POPOVER_WIDTH - VIEWPORT_MARGIN;
    }
    left = Math.max(VIEWPORT_MARGIN, Math.min(left, window.innerWidth - POPOVER_WIDTH - VIEWPORT_MARGIN));

    let top = rect.top;
    if (top + POPOVER_HEIGHT > window.innerHeight - VIEWPORT_MARGIN) {
      top = Math.max(VIEWPORT_MARGIN, window.innerHeight - POPOVER_HEIGHT - VIEWPORT_MARGIN);
    }

    position = { top, left };
  };

  const show = () => {
    updatePosition();
    open = true;
  };

  const hide = () => {
    open = false;
  };

  const toggle = () => {
    if (open) {
      hide();
    } else {
      show();
    }
  };

  const isInside = (target: EventTarget | null): boolean => {
    if (!(target instanceof Node)) {
      return false;
    }
    return !!badgeElement?.contains(target) || !!tipElement?.contains(target);
  };
</script>

<svelte:document
  onkeydown={(event) => {
    if (event.key === 'Escape') {
      hide();
    }
  }}
  onclick={(event) => {
    if (open && !isInside(event.target)) {
      hide();
    }
  }}
/>

{#if visible}
  <div
    role="group"
    aria-label={$t('ai_dedup_why_not_keep')}
    class="absolute inset-e-1 top-1 z-20 text-start"
    onmouseenter={show}
    onmouseleave={hide}
  >
    <button
      bind:this={badgeElement}
      type="button"
      class="grid size-5 place-items-center rounded-full border border-white/85 bg-white/95 text-[12px] leading-none font-bold text-[#e8734a] italic shadow-[0_3px_10px_rgba(30,41,59,0.18)] transition-transform hover:scale-110 focus-visible:scale-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#e8734a]"
      aria-label={$t('ai_dedup_why_not_keep')}
      aria-describedby={open ? tipId : undefined}
      aria-expanded={open}
      onfocus={show}
      onblur={hide}
      onclick={(event) => {
        event.stopPropagation();
        toggle();
      }}
    >
      &#9432;
    </button>

    {#if open}
      <div
        bind:this={tipElement}
        id={tipId}
        role="tooltip"
        class="fixed z-50 max-h-[calc(100vh-1rem)] overflow-y-auto rounded-xl border border-[#e6ecf5] bg-white p-3.5 text-start text-[#1e293b] shadow-[0_18px_46px_rgba(45,60,105,0.18)]"
        style="top: {position.top}px; left: {position.left}px; width: {POPOVER_WIDTH}px"
      >
        <div class="flex items-center justify-between gap-2">
          <h4 class="flex items-center gap-1.5 text-[12px] font-semibold">
            <span class="h-3 w-[3px] rounded-full bg-[#e8734a]"></span>
            {$t('ai_dedup_why_not_keep')}
          </h4>
          <button
            type="button"
            class="rounded-sm px-1 text-[11px] text-[#8a98ad] hover:text-[#1e293b]"
            aria-label={$t('ai_dedup_close')}
            onclick={(event) => {
              event.stopPropagation();
              hide();
            }}
          >
            &times;
          </button>
        </div>

        {#if lowConfidence}
          <p class="mt-2 rounded-md bg-[#fff7e6] px-2 py-1.5 text-[11px] text-[#b45309]">
            {$t('ai_dedup_low_confidence_hint')}
          </p>
        {/if}

        <p class="mt-2 text-[12px] leading-relaxed text-[#52627a]">{reason}</p>

        {#if view.score.defects.length > 0}
          <div class="mt-2 flex flex-wrap gap-1">
            {#each view.score.defects as defect (defect)}
              <span class="rounded-md bg-[#fff0e9] px-1.5 py-0.5 text-[10px] text-[#e8734a]">{defect}</span>
            {/each}
          </div>
        {/if}

        <div
          class="mt-2.5 flex justify-between border-t border-dashed border-[#e6ecf5] pt-2 text-[11px] text-[#8a98ad]"
        >
          <span>{$t('ai_dedup_score_gap', { values: { gap } })}</span>
          <b class="font-semibold text-[#52627a]">
            {$t('ai_dedup_confidence', { values: { value: view.score.confidence.toFixed(2) } })}
          </b>
        </div>

        <p class="mt-2 text-[11px] text-[#6366f1]">{$t('ai_dedup_keep_hint')}</p>
      </div>
    {/if}
  </div>
{/if}
