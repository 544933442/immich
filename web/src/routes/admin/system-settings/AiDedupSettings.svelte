<script lang="ts">
  import SettingInputField from '#lib/components/shared-components/settings/SettingInputField.svelte';
  import SettingSwitch from '#lib/components/shared-components/settings/SettingSwitch.svelte';
  import SettingButtonsRow from '#lib/components/shared-components/settings/SystemConfigButtonRow.svelte';
  import { SettingInputFieldType } from '#lib/constants.ts';
  import { featureFlagsManager } from '#lib/managers/feature-flags-manager.svelte.ts';
  import { createPreloadedQuery } from '#lib/queries/client.ts';
  import { getAdminConfigQuery } from '#lib/queries/config-admin.query.ts';
  import { handleError } from '#lib/utils/handle-error.ts';
  import {
    deleteAiDedupCredential,
    deleteAiDedupScores,
    getAiDedupCredential,
    getAiDedupUsage,
    putAiDedupCredential,
    testAiDedupConnection,
    type AiDedupCredentialStatusDto,
    type AiDedupTestResultDto,
    type AiDedupUsageDto,
  } from '@immich/sdk';
  import { Button, toastManager } from '@immich/ui';
  import { cloneDeep, isEqual } from 'lodash-es';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { fade } from 'svelte/transition';
  import AiDedupPromptReset from './AiDedupPromptReset.svelte';
  import SettingSelect from './SettingSelect.svelte';
  import SettingTextarea from './SettingTextarea.svelte';

  /**
  Admin "AI dedup" settings section. Every field maps 1:1 to an `aiDedup.*`
  config key. The apiKey is a separate transient state: it is never written to
  configToEdit, never exported and never logged (D3).
  */
  const query = createPreloadedQuery(getAdminConfigQuery);
  const config = $derived(query.data);

  const disabled = $derived(featureFlagsManager.value.configFile);
  let configToEdit = $state(cloneDeep(config));
  let allowedHostsText = $state((config.aiDedup?.allowedHosts ?? []).join(', '));

  let credential = $state<AiDedupCredentialStatusDto>({ configured: false, masked: '', updatedAt: '' });
  let apiKeyInput = $state('');
  let usage = $state<AiDedupUsageDto | null>(null);
  let testResult = $state<AiDedupTestResultDto | null>(null);
  let busy = $state(false);
  let showResetDialog = $state(false);

  const loadStatus = async () => {
    try {
      const [credentialStatus, usageStatus] = await Promise.all([getAiDedupCredential(), getAiDedupUsage({})]);
      credential = credentialStatus;
      usage = usageStatus;
    } catch (error) {
      handleError(error, $t('ai_dedup_unconfigured'));
    }
  };

  onMount(() => void loadStatus());

  // [ai-dedup] Normalize the comma-separated allowlist before the shared save row runs.
  const syncBeforeSave = (): Promise<boolean> => {
    configToEdit.aiDedup.allowedHosts = allowedHostsText
      .split(',')
      .map((host) => host.trim())
      .filter(Boolean);
    return Promise.resolve(true);
  };

  const saveApiKey = async () => {
    if (!apiKeyInput) {
      return;
    }
    busy = true;
    try {
      credential = await putAiDedupCredential({ aiDedupCredentialDto: { apiKey: apiKeyInput } });
      apiKeyInput = '';
      toastManager.primary($t('ai_dedup_key_saved'));
    } catch (error) {
      handleError(error, $t('ai_dedup_unconfigured'));
    } finally {
      busy = false;
    }
  };

  const clearApiKey = async () => {
    busy = true;
    try {
      await deleteAiDedupCredential();
      credential = { configured: false, masked: '', updatedAt: '' };
      apiKeyInput = '';
      toastManager.primary($t('ai_dedup_key_cleared'));
    } catch (error) {
      handleError(error, $t('ai_dedup_unconfigured'));
    } finally {
      busy = false;
    }
  };

  // [ai-dedup] Turn raw reason enums (e.g. NO_VISION) into an actionable message.
  // Static keys keep svelte-i18n's literal-key type happy.
  const testReasonKeys = {
    AUTH: 'ai_dedup_test_reason_auth',
    TIMEOUT: 'ai_dedup_test_reason_timeout',
    NO_VISION: 'ai_dedup_test_reason_no_vision',
    NETWORK: 'ai_dedup_test_reason_network',
    SSRF_BLOCKED: 'ai_dedup_test_reason_ssrf_blocked',
    UNKNOWN: 'ai_dedup_test_reason_unknown',
  } as const;
  const testReasonLabel = (reason = 'UNKNOWN') =>
    $t(testReasonKeys[reason as keyof typeof testReasonKeys] ?? testReasonKeys.UNKNOWN);

  const testConnection = async () => {
    busy = true;
    try {
      // Test with the values currently in the form: an admin who typed a new key or
      // baseURL but has not saved yet would otherwise probe the OLD (or no) credential
      // and get a misleading "connection failed".
      testResult = await testAiDedupConnection({
        aiDedupTestConnectionDto: {
          baseURL: configToEdit.aiDedup.baseURL,
          model: configToEdit.aiDedup.model,
          apiKey: apiKeyInput || undefined,
        },
      });
    } catch (error) {
      handleError(error, $t('ai_dedup_test_failed', { values: { reason: testReasonLabel('UNKNOWN') } }));
      testResult = { ok: false, latencyMs: 0 };
    } finally {
      busy = false;
    }
  };

  const clearScores = async () => {
    busy = true;
    try {
      await deleteAiDedupScores({ aiDedupDeleteScoresDto: { includeUsage: false } });
      toastManager.primary($t('ai_dedup_scores_cleared'));
      await loadStatus();
    } catch (error) {
      handleError(error, $t('ai_dedup_unconfigured'));
    } finally {
      busy = false;
    }
  };

  const clearAllData = async () => {
    busy = true;
    try {
      await deleteAiDedupScores({ aiDedupDeleteScoresDto: { includeUsage: true } });
      await deleteAiDedupCredential();
      credential = { configured: false, masked: '', updatedAt: '' };
      apiKeyInput = '';
      toastManager.primary($t('ai_dedup_scores_cleared'));
      await loadStatus();
    } catch (error) {
      handleError(error, $t('ai_dedup_unconfigured'));
    } finally {
      busy = false;
    }
  };

  const copyPrompt = async () => {
    await navigator.clipboard.writeText(configToEdit.aiDedup?.prompt ?? '');
    toastManager.primary($t('ai_dedup_prompt_copied'));
  };
</script>

<div class="mt-2">
  <div in:fade={{ duration: 500 }}>
    <form autocomplete="off" class="mx-4 mt-4" onsubmit={(event) => event.preventDefault()}>
      <div class="flex flex-col gap-4">
        <SettingSwitch
          title={$t('ai_dedup_enabled')}
          subtitle={$t('ai_dedup_enabled_description')}
          {disabled}
          bind:checked={configToEdit.aiDedup.enabled}
          isEdited={configToEdit.aiDedup.enabled !== config.aiDedup.enabled}
        />

        <p class="rounded-lg bg-[#fff7e6] p-2 text-[12px] text-[#b45309]">{$t('ai_dedup_privacy_notice')}</p>

        <SettingSwitch
          title={$t('ai_dedup_privacy_acknowledged')}
          {disabled}
          bind:checked={configToEdit.aiDedup.privacyAcknowledged}
          isEdited={configToEdit.aiDedup.privacyAcknowledged !== config.aiDedup.privacyAcknowledged}
        />

        <hr />

        <h4 class="text-sm font-semibold">{$t('ai_dedup_model_section')}</h4>

        <SettingSelect
          label={$t('ai_dedup_provider')}
          name="ai-dedup-provider"
          bind:value={configToEdit.aiDedup.provider}
          options={[{ value: 'openai-compatible', text: 'OpenAI compatible (chat/completions + vision)' }]}
          {disabled}
          isEdited={configToEdit.aiDedup.provider !== config.aiDedup.provider}
        />

        <SettingInputField
          inputType={SettingInputFieldType.TEXT}
          label={$t('ai_dedup_base_url')}
          bind:value={configToEdit.aiDedup.baseURL}
          {disabled}
          isEdited={configToEdit.aiDedup.baseURL !== config.aiDedup.baseURL}
        />

        <SettingInputField
          inputType={SettingInputFieldType.TEXT}
          label={$t('ai_dedup_model')}
          bind:value={configToEdit.aiDedup.model}
          {disabled}
          isEdited={configToEdit.aiDedup.model !== config.aiDedup.model}
        />

        <SettingInputField
          inputType={SettingInputFieldType.PASSWORD}
          label={$t('ai_dedup_api_key')}
          description={credential.configured
            ? $t('ai_dedup_key_masked', { values: { masked: credential.masked } })
            : $t('ai_dedup_key_not_configured')}
          bind:value={apiKeyInput}
          {disabled}
        />

        <div class="flex flex-wrap gap-2">
          <Button size="small" onclick={saveApiKey} disabled={disabled || busy || !apiKeyInput}>
            {$t('ai_dedup_update_key')}
          </Button>
          <Button
            size="small"
            color="danger"
            onclick={clearApiKey}
            disabled={disabled || busy || !credential.configured}
          >
            {$t('ai_dedup_clear_key')}
          </Button>
          <Button size="small" color="secondary" onclick={testConnection} disabled={disabled || busy}>
            {$t('ai_dedup_test_connection')}
          </Button>
        </div>

        {#if testResult}
          <p class="text-[12px] {testResult.ok ? 'text-[#0ea5a4]' : 'text-[#e8734a]'}">
            {testResult.ok
              ? $t('ai_dedup_test_success', { values: { latency: testResult.latencyMs } })
              : $t('ai_dedup_test_failed', { values: { reason: testReasonLabel(testResult.reason) } })}
          </p>
        {/if}

        <div class="grid gap-3 sm:grid-cols-2">
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_timeout')}
            bind:value={configToEdit.aiDedup.timeoutMs}
            min={1000}
            max={120_000}
            {disabled}
            isEdited={configToEdit.aiDedup.timeoutMs !== config.aiDedup.timeoutMs}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_max_concurrency')}
            bind:value={configToEdit.aiDedup.maxConcurrency}
            min={1}
            max={8}
            {disabled}
            isEdited={configToEdit.aiDedup.maxConcurrency !== config.aiDedup.maxConcurrency}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_max_groups')}
            bind:value={configToEdit.aiDedup.maxGroupsPerRequest}
            min={1}
            {disabled}
            isEdited={configToEdit.aiDedup.maxGroupsPerRequest !== config.aiDedup.maxGroupsPerRequest}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_max_images')}
            bind:value={configToEdit.aiDedup.maxImagesPerGroup}
            min={2}
            max={64}
            {disabled}
            isEdited={configToEdit.aiDedup.maxImagesPerGroup !== config.aiDedup.maxImagesPerGroup}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_max_image_dimension')}
            bind:value={configToEdit.aiDedup.maxImageDimension}
            min={256}
            max={2048}
            {disabled}
            isEdited={configToEdit.aiDedup.maxImageDimension !== config.aiDedup.maxImageDimension}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_image_quality')}
            bind:value={configToEdit.aiDedup.imageQuality}
            min={1}
            max={100}
            {disabled}
            isEdited={configToEdit.aiDedup.imageQuality !== config.aiDedup.imageQuality}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_max_tokens')}
            bind:value={configToEdit.aiDedup.maxTokens}
            min={1}
            {disabled}
            isEdited={configToEdit.aiDedup.maxTokens !== config.aiDedup.maxTokens}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_temperature')}
            bind:value={configToEdit.aiDedup.temperature}
            disabled={true}
          />
        </div>

        <hr />

        <h4 class="text-sm font-semibold">{$t('ai_dedup_prompt_section')}</h4>

        <div class="flex flex-wrap items-center gap-2 text-[12px]">
          <span class="rounded-full bg-[#eef0ff] px-2 py-0.5 text-[#6366f1]">
            {$t('ai_dedup_prompt_version', { values: { version: configToEdit.aiDedup.promptVersion } })}
          </span>
          <Button size="small" variant="ghost" color="secondary" onclick={copyPrompt}>
            {$t('ai_dedup_copy_prompt')}
          </Button>
        </div>

        <SettingTextarea
          label={$t('ai_dedup_prompt_template_readonly')}
          bind:value={configToEdit.aiDedup.prompt}
          disabled={true}
        />

        <SettingTextarea
          label={$t('ai_dedup_strategy_hint')}
          description={$t('ai_dedup_strategy_hint_description')}
          bind:value={configToEdit.aiDedup.strategyHint}
          {disabled}
          isEdited={configToEdit.aiDedup.strategyHint !== config.aiDedup.strategyHint}
        />

        <div class="flex flex-wrap gap-2">
          <Button size="small" color="secondary" onclick={() => (showResetDialog = true)} {disabled}>
            {$t('ai_dedup_reset_prompt')}
          </Button>
        </div>

        <hr />

        <h4 class="text-sm font-semibold">{$t('ai_dedup_strategy_section')}</h4>

        <SettingSelect
          label={$t('ai_dedup_keep_count')}
          name="ai-dedup-keep-count"
          bind:value={configToEdit.aiDedup.keepCount}
          options={[
            { value: 1, text: '1' },
            { value: 2, text: '2' },
            { value: 3, text: '3' },
          ]}
          number={true}
          {disabled}
          isEdited={configToEdit.aiDedup.keepCount !== config.aiDedup.keepCount}
        />

        <SettingSelect
          label={$t('ai_dedup_fallback_strategy')}
          name="ai-dedup-fallback-strategy"
          bind:value={configToEdit.aiDedup.fallbackStrategy}
          options={[
            { value: 'heuristic', text: 'Heuristic (existing smart recommendation)' },
            { value: 'manual', text: 'Manual selection only' },
          ]}
          {disabled}
          isEdited={configToEdit.aiDedup.fallbackStrategy !== config.aiDedup.fallbackStrategy}
        />

        <SettingTextarea
          label={$t('ai_dedup_allowed_hosts')}
          description={$t('ai_dedup_allowed_hosts_description')}
          bind:value={allowedHostsText}
          {disabled}
          isEdited={!isEqual(configToEdit.aiDedup.allowedHosts, config.aiDedup.allowedHosts)}
        />

        <SettingInputField
          inputType={SettingInputFieldType.NUMBER}
          label={$t('ai_dedup_low_confidence_threshold')}
          bind:value={configToEdit.aiDedup.lowConfidenceThreshold}
          min={0}
          max={1}
          step="0.05"
          {disabled}
          isEdited={configToEdit.aiDedup.lowConfidenceThreshold !== config.aiDedup.lowConfidenceThreshold}
        />

        <SettingInputField
          inputType={SettingInputFieldType.NUMBER}
          label={$t('ai_dedup_cache_ttl_days')}
          bind:value={configToEdit.aiDedup.cacheTtlDays}
          min={1}
          max={365}
          {disabled}
          isEdited={configToEdit.aiDedup.cacheTtlDays !== config.aiDedup.cacheTtlDays}
        />

        <hr />

        <h4 class="text-sm font-semibold">{$t('ai_dedup_quota_section')}</h4>

        <div class="grid gap-3 sm:grid-cols-2">
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_daily_call_limit')}
            bind:value={configToEdit.aiDedup.dailyCallLimitPerUser}
            min={1}
            {disabled}
            isEdited={configToEdit.aiDedup.dailyCallLimitPerUser !== config.aiDedup.dailyCallLimitPerUser}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_monthly_budget')}
            bind:value={configToEdit.aiDedup.monthlyBudgetAlert}
            min={0}
            {disabled}
            isEdited={configToEdit.aiDedup.monthlyBudgetAlert !== config.aiDedup.monthlyBudgetAlert}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_cost_per_1k_input')}
            bind:value={configToEdit.aiDedup.costPer1kInputTokens}
            min={0}
            step="0.0001"
            {disabled}
            isEdited={configToEdit.aiDedup.costPer1kInputTokens !== config.aiDedup.costPer1kInputTokens}
          />
          <SettingInputField
            inputType={SettingInputFieldType.NUMBER}
            label={$t('ai_dedup_cost_per_1k_output')}
            bind:value={configToEdit.aiDedup.costPer1kOutputTokens}
            min={0}
            step="0.0001"
            {disabled}
            isEdited={configToEdit.aiDedup.costPer1kOutputTokens !== config.aiDedup.costPer1kOutputTokens}
          />
        </div>

        <SettingSwitch
          title={$t('ai_dedup_auto_disable_on_limit')}
          {disabled}
          bind:checked={configToEdit.aiDedup.autoDisableOnLimit}
          isEdited={configToEdit.aiDedup.autoDisableOnLimit !== config.aiDedup.autoDisableOnLimit}
        />

        {#if usage}
          <div class="rounded-lg bg-[#f8faff] p-3 text-[12px] text-[#52627a]">
            <div class="font-medium">{$t('ai_dedup_usage')}</div>
            <p class="mt-1">
              {$t('ai_dedup_today_calls', { values: { count: usage.today.calls } })} ·
              {$t('ai_dedup_month_calls', { values: { count: usage.month.calls } })} ·
              {$t('ai_dedup_estimated_cost', { values: { cost: usage.month.estimatedCostUsd.toFixed(4) } })}
            </p>
          </div>
        {/if}

        <hr />

        <h4 class="text-sm font-semibold">{$t('ai_dedup_data_section')}</h4>

        <div class="flex flex-wrap gap-2">
          <Button size="small" color="secondary" onclick={clearScores} disabled={disabled || busy}>
            {$t('ai_dedup_clear_scores')}
          </Button>
          <Button size="small" color="danger" onclick={clearAllData} disabled={disabled || busy}>
            {$t('ai_dedup_clear_all_data')}
          </Button>
        </div>

        <SettingButtonsRow bind:configToEdit keys={['aiDedup']} {disabled} onBeforeSave={syncBeforeSave} />
      </div>
    </form>
  </div>
</div>

{#if showResetDialog}
  <AiDedupPromptReset bind:configToEdit onClose={() => (showResetDialog = false)} />
{/if}
