<script lang="ts">
  import { createPreloadedQuery } from '#lib/queries/client.ts';
  import { getAdminConfigDefaultsQuery } from '#lib/queries/config-admin.query.ts';
  import { handleError } from '#lib/utils/handle-error.ts';
  import { deleteAiDedupScores, type AdminConfigDto } from '@immich/sdk';
  import { Button, toastManager } from '@immich/ui';
  import { cloneDeep, pick } from 'lodash-es';
  import { t } from 'svelte-i18n';

  /**
  Second-step confirmation for restoring the default AI dedup prompt.
  
  It deliberately reuses the exact `handleResetToDefault` recipe from
  `SystemConfigButtonRow.svelte:39-42` — `cloneDeep(pick(defaults, keys))`
  applied to `configToEdit` — plus the existing
  `getAdminConfigDefaultsQuery()`. No new server endpoint is involved.
  */
  interface Props {
    configToEdit: AdminConfigDto;
    onClose: () => void;
  }

  let { configToEdit = $bindable(), onClose }: Props = $props();

  const query = createPreloadedQuery(getAdminConfigDefaultsQuery);
  const defaults = $derived(query.data);

  let clearScores = $state(false);
  let busy = $state(false);

  const currentVersion = $derived(configToEdit.aiDedup?.promptVersion ?? '');
  const defaultVersion = $derived(defaults.aiDedup?.promptVersion ?? '');
  const currentHint = $derived(configToEdit.aiDedup?.strategyHint ?? '');
  const defaultHint = $derived(defaults.aiDedup?.strategyHint ?? '');
  const isEdited = $derived(currentHint !== defaultHint);

  const confirmReset = async () => {
    if (busy) {
      return;
    }

    busy = true;
    try {
      // Mirrors `SystemConfigButtonRow.handleResetToDefault` (pick(defaults, keys)), but
      // scoped to the prompt-related keys ONLY: resetting the whole aiDedup block would
      // also wipe baseURL/model/quota/allowedHosts/privacyAcknowledged.
      configToEdit = {
        ...configToEdit,
        aiDedup: {
          ...configToEdit.aiDedup,
          ...cloneDeep(pick(defaults.aiDedup, ['prompt', 'promptVersion', 'strategyHint'])),
        },
      };

      if (clearScores) {
        // Only the score cache, never the usage/cost statistics (includeUsage defaults
        // to true server-side and would wipe every user's accounting).
        await deleteAiDedupScores({ aiDedupDeleteScoresDto: { includeUsage: false } });
      }

      toastManager.primary($t('ai_dedup_reset_prompt_confirm'));
      onClose();
    } catch (error) {
      handleError(error, $t('errors.something_went_wrong'));
    } finally {
      busy = false;
    }
  };
</script>

<div
  class="fixed inset-0 z-60 grid place-items-center bg-[#1e293b]/25 p-4"
  role="presentation"
  onclick={(event) => {
    if (event.target === event.currentTarget) {
      onClose();
    }
  }}
>
  <div
    class="w-full max-w-lg rounded-2xl border border-[#e6ecf5] bg-linear-to-br from-white to-[#f6f8fc] p-5 text-[#1e293b] shadow-[0_18px_46px_rgba(45,60,105,0.18)]"
    role="dialog"
    aria-modal="true"
    aria-label={$t('ai_dedup_reset_prompt')}
  >
    <h3 class="text-base font-semibold">{$t('ai_dedup_reset_prompt')}</h3>

    <dl class="mt-4 grid grid-cols-2 gap-2 text-[12px]">
      <div class="rounded-lg bg-white p-2">
        <dt class="text-[#8a98ad]">{$t('ai_dedup_current_prompt_version')}</dt>
        <dd class="mt-1 font-medium">{currentVersion}</dd>
      </div>
      <div class="rounded-lg bg-white p-2">
        <dt class="text-[#8a98ad]">{$t('ai_dedup_default_prompt_version')}</dt>
        <dd class="mt-1 font-medium">{defaultVersion}</dd>
      </div>
    </dl>

    <div class="mt-3 rounded-lg bg-white p-3 text-[12px]">
      <div class="font-medium">{$t('ai_dedup_reset_diff_summary')}</div>
      <p class="mt-1 wrap-break-word text-[#52627a]">
        {isEdited ? `「${currentHint}」 → 「${defaultHint || '—'}」` : $t('ai_dedup_reset_no_diff')}
      </p>
    </div>

    <p class="mt-3 rounded-lg bg-[#fff7e6] p-2 text-[12px] text-[#b45309]">
      {$t('ai_dedup_reset_prompt_warning')}
    </p>

    <label class="mt-3 flex items-center gap-2 text-[12px] text-[#52627a]">
      <input type="checkbox" bind:checked={clearScores} class="size-4" />
      {$t('ai_dedup_reset_clear_scores')}
    </label>

    <div class="mt-5 flex justify-end gap-2">
      <Button size="small" color="secondary" onclick={onClose} disabled={busy}>{$t('cancel')}</Button>
      <Button size="small" color="primary" onclick={confirmReset} disabled={busy}>
        {$t('confirm')}
      </Button>
    </div>
  </div>
</div>
