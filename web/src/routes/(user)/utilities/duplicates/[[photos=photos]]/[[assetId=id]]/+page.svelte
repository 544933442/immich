<script lang="ts">
  import { shortcuts } from '#lib/actions/shortcut.ts';
  import UserPageLayout from '#lib/components/layouts/UserPageLayout.svelte';
  import { assetViewerManager } from '#lib/managers/asset-viewer-manager.svelte.ts';
  import { languageManager } from '#lib/managers/language-manager.svelte.ts';
  import ShortcutsModal from '#lib/modals/ShortcutsModal.svelte';
  import { createPreloadedQuery } from '#lib/queries/client.ts';
  import { getUserConfigQuery } from '#lib/queries/config-user.query.ts';
  import { Route } from '#lib/route.ts';
  import { locale } from '#lib/stores/preferences.store.ts';
  // [ai-dedup]
  // [ai-dedup]
  // [ai-dedup]
  import {
    buildAiDedupViewContext,
    mergeAiKeepIds,
    provideAiDedupViewContext,
    type AiDedupGroupResultDto,
    type AiDedupGroupResultMap,
  } from '#lib/utils/ai-dedup.ts';
  // [ai-dedup]
  import { handleError } from '#lib/utils/handle-error.ts';
  import { createStack, deleteDuplicates, resolveDuplicates, updateAssets, type AssetResponseDto } from '@immich/sdk';
  import { Button, HStack, IconButton, Text, modalManager, toastManager } from '@immich/ui';
  import {
    mdiCheckOutline,
    mdiChevronLeft,
    mdiChevronRight,
    mdiKeyboard,
    mdiPageFirst,
    mdiPageLast,
    mdiTrashCanOutline,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import type { PageData } from './$types';
  import AiRecommendationBar from './AiRecommendationBar.svelte'; // [ai-dedup]
  import DuplicatesCompareControl from './DuplicatesCompareControl.svelte';
  import LinkToDocs from './LinkToDocs.svelte';

  // [ai-dedup]

  const query = createPreloadedQuery(getUserConfigQuery);
  const config = $derived(query.data);

  interface Props {
    data: PageData;
  }

  let { data = $bindable() }: Props = $props();

  interface Shortcuts {
    general: ExplainedShortcut[];
    actions: ExplainedShortcut[];
  }
  interface ExplainedShortcut {
    key: string[];
    action: string;
    info?: string;
  }

  const duplicateShortcuts: Shortcuts = {
    general: [],
    actions: [
      { key: ['a'], action: $t('select_all_duplicates') },
      { key: ['s'], action: $t('view') },
      { key: ['d'], action: $t('unselect_all_duplicates') },
      { key: ['⇧', 'c'], action: $t('resolve_duplicates') },
      { key: ['⇧', 's'], action: $t('stack_duplicates') },
    ],
  };

  let duplicates = $state(data.duplicates);
  let showMore = $state(false);

  const correctDuplicatesIndex = (index: number) => {
    return Math.max(0, Math.min(index, duplicates.length - 1));
  };

  let duplicatesIndex = $derived(
    (() => {
      const indexParam = page.url.searchParams.get('index') ?? '0';
      const parsedIndex = Math.trunc(Number(indexParam));
      return correctDuplicatesIndex(Number.isNaN(parsedIndex) ? 0 : parsedIndex);
    })(),
  );

  let hasDuplicates = $derived(duplicates.length > 0);
  const withConfirmation = async (callback: () => Promise<void>, prompt?: string, confirmText?: string) => {
    if (prompt && confirmText) {
      const isConfirmed = await modalManager.showDialog({ prompt, confirmText });
      if (!isConfirmed) {
        return;
      }
    }

    try {
      return await callback();
    } catch (error) {
      handleError(error, $t('errors.unable_to_resolve_duplicate'));
    }
  };

  const deletedNotification = (trashedCount: number) => {
    if (!trashedCount) {
      return;
    }

    const message = config.trash.enabled
      ? $t('assets_moved_to_trash_count', { values: { count: trashedCount } })
      : $t('permanently_deleted_assets_count', { values: { count: trashedCount } });
    toastManager.primary(message);
  };

  const handleResolve = async (duplicateId: string, duplicateAssetIds: string[], trashIds: string[]) => {
    const forceDelete = !config.trash.enabled;
    const shouldConfirmDelete = trashIds.length > 0 && forceDelete;

    return withConfirmation(
      async () => {
        const keepAssetIds = duplicateAssetIds.filter((id) => !trashIds.includes(id));

        const response = await resolveDuplicates({
          duplicateResolveDto: {
            groups: [{ duplicateId, keepAssetIds, trashAssetIds: trashIds }],
          },
        });

        const { success, error, errorMessage = error } = response[0];
        if (!success) {
          throw new Error(errorMessage);
        }

        duplicates = duplicates.filter((duplicate) => duplicate.duplicateId !== duplicateId);

        deletedNotification(trashIds.length);
        await navigateToIndex(duplicatesIndex);
      },
      shouldConfirmDelete ? $t('delete_duplicates_confirmation') : undefined,
      shouldConfirmDelete ? $t('permanently_delete') : undefined,
    );
  };

  const handleStack = async (duplicateId: string, assets: AssetResponseDto[]) => {
    const assetIds = assets.map((asset) => asset.id);
    await createStack({ stackCreateDto: { assetIds } });
    await updateAssets({ assetBulkUpdateDto: { ids: assetIds, duplicateId: null } });
    duplicates = duplicates.filter((duplicate) => duplicate.duplicateId !== duplicateId);
    await navigateToIndex(duplicatesIndex);
  };

  const handleDeduplicateAll = async () => {
    // Use server-provided suggestedKeepAssetIds from each group
    const idsToDelete = duplicates.flatMap((group) => {
      const keepIds = new Set(group.suggestedKeepAssetIds);
      return group.assets.map((asset) => asset.id).filter((id) => !keepIds.has(id));
    });

    let prompt, confirmText;
    if (config.trash.enabled) {
      prompt = $t('bulk_trash_duplicates_confirmation', { values: { count: idsToDelete.length } });
      confirmText = $t('confirm');
    } else {
      prompt = $t('bulk_delete_duplicates_confirmation', { values: { count: idsToDelete.length } });
      confirmText = $t('permanently_delete');
    }

    return withConfirmation(
      async () => {
        // Resolve all groups in a single batch request
        const response = await resolveDuplicates({
          duplicateResolveDto: {
            groups: duplicates.map((group) => {
              const keepIds = new Set(group.suggestedKeepAssetIds);
              return {
                duplicateId: group.duplicateId,
                keepAssetIds: group.suggestedKeepAssetIds,
                trashAssetIds: group.assets.map((asset) => asset.id).filter((id) => !keepIds.has(id)),
              };
            }),
          },
        });

        // Count failures and show appropriate message
        const failedCount = response.filter(({ success }) => !success).length;
        if (failedCount > 0) {
          toastManager.danger($t('errors.unable_to_resolve_duplicate'));
        }

        duplicates = [];

        deletedNotification(idsToDelete.length);

        await goto(Route.duplicatesUtility());
      },
      prompt,
      confirmText,
    );
  };

  const handleKeepAll = async () => {
    const ids = duplicates.map(({ duplicateId }) => duplicateId);
    return withConfirmation(
      async () => {
        await deleteDuplicates({ bulkIdsDto: { ids } });

        duplicates = [];

        toastManager.primary($t('resolved_all_duplicates'));
        await goto(Route.duplicatesUtility());
      },
      $t('bulk_keep_duplicates_confirmation', { values: { count: ids.length } }),
      $t('confirm'),
    );
  };

  const handleFirst = () => navigateToIndex(0);
  const handlePrevious = () => navigateToIndex(Math.max(duplicatesIndex - 1, 0));
  const handleNext = async () => navigateToIndex(Math.min(duplicatesIndex + 1, duplicates.length - 1));
  const handleLast = () => navigateToIndex(duplicates.length - 1);

  const navigateToIndex = async (index: number) =>
    goto(Route.duplicatesUtility({ index: correctDuplicatesIndex(index) }));

  // [ai-dedup] Publish the AI view via context (Svelte 5 forbids a second $props() call).
  let aiResults = $state<AiDedupGroupResultMap>(data.aiResults ?? {}); // [ai-dedup]
  const aiView = $state(buildAiDedupViewContext(aiResults, !!data.aiEnabled)); // [ai-dedup]
  provideAiDedupViewContext(aiView); // [ai-dedup]

  // [ai-dedup] Apply a re-evaluated group to the in-memory duplicates copy.
  const applyReevaluatedGroup = (result: AiDedupGroupResultDto) => {
    // [ai-dedup] Discard stale responses: the user may have navigated to another group
    // (or resolved this one) while the force-evaluation was in flight.
    if (duplicates.every((group) => group.duplicateId !== result.duplicateId)) {
      // [ai-dedup]
      return;
    }
    const response = { degradedCount: 0, quota: { limit: 0, used: 0 }, results: [result], truncatedCount: 0 }; // [ai-dedup]
    duplicates.splice(0, duplicates.length, ...mergeAiKeepIds(duplicates, response)); // [ai-dedup]
    aiResults[result.duplicateId] = result; // [ai-dedup]
    Object.assign(aiView.byAssetId, buildAiDedupViewContext({ [result.duplicateId]: result }, true).byAssetId); // [ai-dedup]
  };

  // [ai-dedup] Append a "go to trash" toast after an AI-assisted bulk cleanup.
  let aiPreviousCount = data.duplicates.length; // [ai-dedup]
  $effect(() => {
    // [ai-dedup]
    const current = duplicates.length; // [ai-dedup]
    if (data.aiEnabled && aiPreviousCount > 0 && current === 0) {
      // [ai-dedup]
      toastManager.primary($t('ai_dedup_cleanup_toast')); // [ai-dedup]
    } // [ai-dedup]
    aiPreviousCount = current; // [ai-dedup]
  }); // [ai-dedup]

  // [ai-dedup] Dedicated bulk-cleanup handler for AI mode. The official
  // handleDeduplicateAll above stays byte-for-byte untouched (A1 / D1): this
  // handler only swaps the confirmation copy and adds the R-11 acknowledgement,
  // while still deleting exclusively through the existing resolveDuplicates.
  const handleAiDeduplicateAll = async () => {
    // [ai-dedup] Q12 hard gate at the deletion layer (defense in depth on top of
    // mergeAiKeepIds): groups the AI evaluated successfully but flagged for manual
    // review are SKIPPED by bulk cleanup, and a group with no keep candidate is
    // never sent to resolve — at least one asset must survive every group.
    const groupsToResolve = duplicates.filter((group) => {
      // [ai-dedup]
      const result = aiResults[group.duplicateId];
      if (result && !result.degraded && result.needsManualReview) {
        // [ai-dedup]
        return false;
      }
      return group.suggestedKeepAssetIds.length > 0;
    });
    const skippedCount = duplicates.length - groupsToResolve.length;

    if (groupsToResolve.length === 0) {
      // [ai-dedup] Nothing can be cleaned up automatically; keep the page untouched.
      toastManager.primary($t('ai_dedup_bulk_all_skipped'));
      return;
    }

    const idsToDelete = groupsToResolve.flatMap((group) => {
      // [ai-dedup]
      const keepIds = new Set(group.suggestedKeepAssetIds); // [ai-dedup]
      return group.assets.map((asset) => asset.id).filter((id) => !keepIds.has(id)); // [ai-dedup]
    }); // [ai-dedup]

    // [ai-dedup] E2 echoes the effective trash flag; the local config is a fallback.
    const trashEnabled = data.aiPrompt?.trashEnabled ?? config.trash.enabled; // [ai-dedup]
    const prompt = trashEnabled // [ai-dedup]
      ? $t('ai_dedup_bulk_trash_confirmation', { values: { count: idsToDelete.length } }) // [ai-dedup]
      : $t('ai_dedup_bulk_delete_confirmation', { values: { count: idsToDelete.length } }); // [ai-dedup]
    const confirmText = trashEnabled ? $t('confirm') : $t('permanently_delete'); // [ai-dedup]

    return withConfirmation(
      // [ai-dedup]
      async () => {
        // [ai-dedup] R-11: with the trash disabled, resolve() deletes permanently.
        if (!trashEnabled) {
          // [ai-dedup]
          const acknowledged = await modalManager.showDialog({
            // [ai-dedup]
            prompt: $t('ai_dedup_bulk_delete_extra_check'), // [ai-dedup]
            confirmText: $t('permanently_delete'), // [ai-dedup]
            confirmColor: 'danger', // [ai-dedup]
          }); // [ai-dedup]
          if (!acknowledged) {
            // [ai-dedup]
            return; // [ai-dedup]
          } // [ai-dedup]
        } // [ai-dedup]

        const response = await resolveDuplicates({
          // [ai-dedup]
          duplicateResolveDto: {
            // [ai-dedup]
            groups: groupsToResolve.map((group) => {
              // [ai-dedup]
              const keepIds = new Set(group.suggestedKeepAssetIds); // [ai-dedup]
              return {
                // [ai-dedup]
                duplicateId: group.duplicateId, // [ai-dedup]
                keepAssetIds: group.suggestedKeepAssetIds, // [ai-dedup]
                trashAssetIds: group.assets.map((asset) => asset.id).filter((id) => !keepIds.has(id)), // [ai-dedup]
              }; // [ai-dedup]
            }), // [ai-dedup]
          }, // [ai-dedup]
        }); // [ai-dedup]

        const failedCount = response.filter(({ success }) => !success).length; // [ai-dedup]
        if (failedCount > 0) {
          // [ai-dedup]
          toastManager.danger($t('errors.unable_to_resolve_duplicate')); // [ai-dedup]
        } // [ai-dedup]

        // [ai-dedup] Keep the skipped groups on the page instead of clearing everything.
        const resolvedIds = new Set(groupsToResolve.map((group) => group.duplicateId)); // [ai-dedup]
        duplicates = duplicates.filter((group) => !resolvedIds.has(group.duplicateId)); // [ai-dedup]

        deletedNotification(idsToDelete.length); // [ai-dedup]
        if (skippedCount > 0) {
          // [ai-dedup] The user must know which groups were deliberately not cleaned up.
          toastManager.primary($t('ai_dedup_bulk_skipped_groups', { values: { count: skippedCount } })); // [ai-dedup]
        }
        await goto(Route.duplicatesUtility()); // [ai-dedup]
      }, // [ai-dedup]
      prompt, // [ai-dedup]
      confirmText, // [ai-dedup]
    ); // [ai-dedup]
  }; // [ai-dedup]
</script>

<svelte:document
  use:shortcuts={assetViewerManager.isViewing
    ? []
    : [
        { shortcut: { key: 'ArrowLeft' }, onShortcut: handlePrevious },
        { shortcut: { key: 'ArrowRight' }, onShortcut: handleNext },
      ]}
/>

<UserPageLayout title={data.meta.title + ` (${duplicates.length.toLocaleString($locale)})`} scrollbar={true}>
  {#snippet buttons()}
    <HStack gap={0}>
      <!-- [ai-dedup] Disabled mode keeps the official button verbatim; enabled mode hides it. -->
      <Button
        leadingIcon={mdiTrashCanOutline}
        onclick={() => handleDeduplicateAll()}
        disabled={!hasDuplicates}
        size="small"
        variant="ghost"
        color="secondary"
        class={data.aiEnabled ? 'hidden' : ''}
      >
        <Text class="hidden md:block">{$t('deduplicate_all')}</Text>
      </Button>
      {#if data.aiEnabled}
        <!-- [ai-dedup] AI confirmation copy + R-11 acknowledgement live in the dedicated handler. -->
        <Button
          leadingIcon={mdiTrashCanOutline}
          onclick={() => handleAiDeduplicateAll()}
          disabled={!hasDuplicates}
          size="small"
          variant="ghost"
          color="secondary"
        >
          <Text class="hidden md:block">{$t('deduplicate_all')}</Text>
        </Button>
      {/if}
      <Button
        leadingIcon={mdiCheckOutline}
        onclick={() => handleKeepAll()}
        disabled={!hasDuplicates}
        size="small"
        variant="ghost"
        color="secondary"
      >
        <Text class="hidden md:block">{$t('keep_all')}</Text>
      </Button>
      <IconButton
        shape="round"
        variant="ghost"
        color="secondary"
        icon={mdiKeyboard}
        title={$t('show_keyboard_shortcuts')}
        onclick={() => modalManager.show(ShortcutsModal, { shortcuts: duplicateShortcuts })}
        aria-label={$t('show_keyboard_shortcuts')}
      />
    </HStack>
  {/snippet}

  <div>
    {#if duplicates && duplicates.length > 0}
      <Text size="small" color="muted" class="mb-4">
        {$t('duplicates_description')}
        <LinkToDocs href="https://docs.immich.app/features/duplicates-utility" />
      </Text>

      <!-- [ai-dedup] Key includes generatedAt so a force re-evaluation rebuilds the compare
           control: otherwise its internal selectedAssetIds would keep the stale pre-selection
           while the badges already show the fresh AI recommendation. -->
      {#key `${duplicates[duplicatesIndex].duplicateId}:${aiResults[duplicates[duplicatesIndex].duplicateId]?.generatedAt ?? ''}`}
        {#if data.aiEnabled}
          <!-- [ai-dedup] -->
          <AiRecommendationBar
            aiEnabled={data.aiEnabled}
            aiPrompt={data.aiPrompt ?? null}
            aiResult={aiResults[duplicates[duplicatesIndex].duplicateId]}
            onReevaluate={applyReevaluatedGroup}
          />
          <!-- [ai-dedup] -->
        {/if}
        <!-- [ai-dedup] -->
        <DuplicatesCompareControl
          assets={duplicates[duplicatesIndex].assets}
          suggestedKeepAssetIds={duplicates[duplicatesIndex].suggestedKeepAssetIds}
          bind:showMore
          onResolve={(duplicateAssetIds, trashIds) =>
            handleResolve(duplicates[duplicatesIndex].duplicateId, duplicateAssetIds, trashIds)}
          onStack={(assets) => handleStack(duplicates[duplicatesIndex].duplicateId, assets)}
          aiResult={aiResults[duplicates[duplicatesIndex].duplicateId]}
        />
        <div class="mx-auto mb-16 max-w-5xl">
          <div class="mb-4 flex w-full place-content-center place-items-center items-center justify-between sm:px-6">
            <div class="flex text-xs text-black">
              <Button
                size="small"
                leadingIcon={languageManager.rtl ? mdiPageLast : mdiPageFirst}
                class="flex place-items-center gap-2 rounded-s-full px-2 sm:px-4"
                onclick={handleFirst}
                disabled={duplicatesIndex === 0}
              >
                {$t('first')}
              </Button>
              <Button
                size="small"
                leadingIcon={languageManager.rtl ? mdiChevronRight : mdiChevronLeft}
                class="flex place-items-center gap-2 rounded-e-full px-2 sm:px-4"
                onclick={handlePrevious}
                disabled={duplicatesIndex === 0}
              >
                {$t('previous')}
              </Button>
            </div>
            <p class="rounded-lg border px-3 py-1 text-xs md:px-6 md:text-sm dark:bg-subtle">
              {duplicatesIndex + 1} / {duplicates.length.toLocaleString($locale)}
            </p>
            <div class="flex text-xs text-black">
              <Button
                size="small"
                trailingIcon={languageManager.rtl ? mdiChevronLeft : mdiChevronRight}
                class="flex place-items-center gap-2 rounded-s-full px-2 sm:px-4"
                onclick={handleNext}
                disabled={duplicatesIndex === duplicates.length - 1}
              >
                {$t('next')}
              </Button>
              <Button
                size="small"
                trailingIcon={languageManager.rtl ? mdiPageFirst : mdiPageLast}
                class="flex place-items-center gap-2 rounded-e-full px-2 sm:px-4"
                onclick={handleLast}
                disabled={duplicatesIndex === duplicates.length - 1}
              >
                {$t('last')}
              </Button>
            </div>
          </div>
        </div>
      {/key}
    {:else}
      <p class="flex place-content-center place-items-center text-center text-lg dark:text-white">
        {$t('no_duplicates_found')}
      </p>
    {/if}
  </div>
</UserPageLayout>
