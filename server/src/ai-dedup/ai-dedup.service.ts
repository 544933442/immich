import { Inject, Injectable } from '@nestjs/common';
import { MapAsset, mapAsset, type AssetResponseDto } from 'src/dtos/asset-response.dto.js';
import type { AuthDto } from 'src/dtos/auth.dto.js';
import type { SystemConfig } from 'src/dtos/config.dto.js';
import { AssetType, Permission } from 'src/enum.js';
import { BaseService } from 'src/services/base.service.js';
import {
  AI_DEDUP_DEFAULT_PROMPT,
  AI_DEDUP_DEGRADED_CACHE_TTL_MS,
  AI_DEDUP_PROMPT_VERSION,
} from 'src/ai-dedup/constants.js';
import {
  CircuitBreaker,
  Semaphore,
  buildAiDedupCacheKey,
  buildMemberHash,
  isFresh,
  isFreshWithinMs,
  isQuotaExceeded,
} from 'src/ai-dedup/circuit-breaker.js';
import { AiDedupCredentialStore, hasEncryptionKey } from 'src/ai-dedup/credential.js';
import {
  AiDedupErrorCode,
  type AiDedupClearResult,
  type AiDedupCredentialStatus,
  type AiDedupDeleteScoresRequest,
  type AiDedupEvaluateRequest,
  type AiDedupEvaluateResponse,
  type AiDedupGroupResult,
  type AiDedupPrompt,
  type AiDedupPurgeResult,
  type AiDedupTestConnectionRequest,
  type AiDedupTestResult,
  type AiDedupUsage,
  type AiDedupUsageQuery,
} from 'src/ai-dedup/dto.js';
import type { AiDedupImagePath } from 'src/ai-dedup/image.js';
import { prepareImages } from 'src/ai-dedup/image.js';
import { AiDedupProviderError, OpenAiCompatibleProvider, validateBaseUrl } from 'src/ai-dedup/openai-compatible.provider.js';
import { buildDegradedResult, parseAndValidate } from 'src/ai-dedup/parse.js';
import { renderPrompt, strategySummary } from 'src/ai-dedup/prompt.js';
import type { AiDedupModelConfig, AiDedupProvider } from 'src/ai-dedup/provider.interface.js';
import { AiDedupRepository } from 'src/ai-dedup/ai-dedup.repository.js';

type AiDedupConfig = SystemConfig['aiDedup'];

interface DuplicateGroup {
  duplicateId: string;
  assets: AssetResponseDto[];
  rawAssets: MapAsset[];
}

const estimateCost = (inputTokens: number, outputTokens: number, config: AiDedupConfig): number =>
  (inputTokens / 1000) * config.costPer1kInputTokens + (outputTokens / 1000) * config.costPer1kOutputTokens;

/**
Orchestration for the AI dedup module: cache, quota, SSRF, per-group degradation.
Extends BaseService (no constructor override) to reuse getConfig/requireAccess/logger and
all existing repositories; the new repository is injected as a property so no existing
file (especially base.service.ts) needs to change.
*/
@Injectable()
export class AiDedupService extends BaseService {
  @Inject(AiDedupRepository)
  private readonly aiDedupRepository!: AiDedupRepository;

  private readonly provider: AiDedupProvider = new OpenAiCompatibleProvider();
  private readonly breaker = new CircuitBreaker(5, 60_000);
  private semaphore = new Semaphore(4);
  private semaphoreMax = 4;
  private credentialStore: AiDedupCredentialStore | null = null;
  /**
  [ai-dedup] A capability mismatch (reasoning model exhausting max_tokens, or a
  text-only model) is not transient: retrying it once per group is slow and costly.
  Suppress further external calls for the same configuration briefly; changing
  baseURL/model/maxTokens/prompt clears the suppression immediately.
  */
  private capabilityFailure: { fingerprint: string; at: number; code: AiDedupErrorCode } | null = null;

  private get credentials(): AiDedupCredentialStore {
    this.credentialStore ??= new AiDedupCredentialStore(this.systemMetadataRepository);
    return this.credentialStore;
  }

  /** E1: evaluate / cache lookup. Never throws as a whole; every group degrades independently. */
  async evaluate(auth: AuthDto, dto: AiDedupEvaluateRequest): Promise<AiDedupEvaluateResponse> {
    let config: AiDedupConfig;
    try {
      const current = await this.getConfig({ withCache: true });
      config = current.aiDedup;
    } catch {
      // Config read failure must never break the duplicates page.
      return {
        results: dto.duplicateIds.map((duplicateId) =>
          buildDegradedResult({ duplicateId, assets: [] }, AiDedupErrorCode.NotConfigured),
        ),
        degradedCount: dto.duplicateIds.length,
        truncatedCount: 0,
        quota: { used: 0, limit: 0 },
      };
    }

    const ids = dto.duplicateIds.slice(0, Math.max(1, config.maxGroupsPerRequest));
    try {
      return await this.evaluateInternal(auth, dto, ids, config);
    } catch (error) {
      // Last-resort guard: C4 forbids any exception from escaping this endpoint.
      this.logger.warn(`[ai-dedup] evaluate degraded as a whole: ${this.errorLabel(error)}`);
      return {
        results: ids.map((duplicateId) =>
          buildDegradedResult({ duplicateId, assets: [] }, AiDedupErrorCode.PartialFailure),
        ),
        degradedCount: ids.length,
        truncatedCount: 0,
        quota: { used: 0, limit: config.dailyCallLimitPerUser },
      };
    }
  }

  /** E2: minimal, non-sensitive prompt/view state for the duplicates page and admin UI. */
  async getPrompt(): Promise<AiDedupPrompt> {
    const full = await this.getConfig({ withCache: true });
    const config = full.aiDedup;
    // [ai-dedup] Show the prompt that is actually in effect (`evaluateOne` renders the same
    // `config.prompt || DEFAULT`), never a hardcoded constant that can drift from reality.
    const effectivePrompt = config.prompt || AI_DEDUP_DEFAULT_PROMPT;
    return {
      enabled: config.enabled,
      version: config.promptVersion || AI_DEDUP_PROMPT_VERSION,
      strategySummary: strategySummary(config.strategyHint),
      promptTemplate: effectivePrompt,
      trashEnabled: full.trash.enabled,
      defaults: {
        promptVersion: AI_DEDUP_PROMPT_VERSION,
        strategyHint: '',
        keepCount: 1,
        fallbackStrategy: 'heuristic',
        lowConfidenceThreshold: 0.5,
        cacheTtlDays: 30,
      },
    };
  }

  /** E7: connectivity probe with a built-in 1x1 image; no real photo, no DB write, no quota. */
  async testConnection(dto: AiDedupTestConnectionRequest): Promise<AiDedupTestResult> {
    const current = await this.getConfig({ withCache: true });
    const config = current.aiDedup;
    let credential = dto.apiKey ?? '';
    if (!credential) {
      try {
        credential = await this.credentials.get();
      } catch {
        return { ok: false, reason: 'UNKNOWN', latencyMs: 0 };
      }
    }

    const modelConfig: AiDedupModelConfig = {
      baseURL: dto.baseURL || config.baseURL,
      model: dto.model || config.model,
      timeoutMs: config.timeoutMs,
      maxTokens: config.maxTokens,
      temperature: 0,
      allowedHosts: config.allowedHosts,
    };
    if (!modelConfig.baseURL || !modelConfig.model) {
      return { ok: false, reason: 'UNKNOWN', latencyMs: 0 };
    }
    return this.provider.testConnection(credential, modelConfig);
  }

  getCredentialStatus(): Promise<AiDedupCredentialStatus> {
    return this.credentials.status();
  }

  putCredential(dto: { apiKey: string }): Promise<AiDedupCredentialStatus> {
    return this.credentials.put(dto.apiKey);
  }

  async clearCredential(): Promise<AiDedupClearResult> {
    await this.credentials.clear();
    this.breaker.reset();
    return { cleared: true };
  }

  /** E6: clear scores (+ usage). Credential is cleared via DELETE /credential separately. */
  async purgeScores(dto: AiDedupDeleteScoresRequest): Promise<AiDedupPurgeResult> {
    const { scoresDeleted, usageDeleted } = await this.aiDedupRepository.purge(dto.ownerId, dto.includeUsage);
    this.breaker.reset();
    return { scoresDeleted, usageDeleted, credentialCleared: false };
  }

  /** E8: usage/cost readout for admins. */
  getUsage(query: AiDedupUsageQuery): Promise<AiDedupUsage> {
    return this.aiDedupRepository.getUsage(query.ownerId, query.month);
  }

  private async evaluateInternal(
    auth: AuthDto,
    dto: AiDedupEvaluateRequest,
    ids: string[],
    config: AiDedupConfig,
  ): Promise<AiDedupEvaluateResponse> {
    const ownerId = auth.user.id;
    const quota = { used: 0, limit: config.dailyCallLimitPerUser };

    // Permission guard first (technical design §12). A failure degrades instead of throwing.
    try {
      await this.requireAccess({ auth, permission: Permission.DuplicateRead, ids });
    } catch {
      this.logger.warn(`[ai-dedup] access check failed for ${ids.length} group(s)`);
      return this.degradeAll(ids, config, AiDedupErrorCode.NoPermission, quota);
    }

    const used = await this.aiDedupRepository.getTodayUsage(ownerId);
    quota.used = used;

    // Static preconditions (enabled / configured / privacy / key / credential / SSRF):
    // when they fail no cache row could ever have been produced, so everything degrades.
    const precondition = await this.checkStaticPreconditions(config);

    const groups = await this.loadGroups(auth, ids);
    if (precondition) {
      // enabled=false / unconfigured => ZERO external requests (A1, E2, E3).
      return this.degradeGroups(groups, ids, config, precondition, quota);
    }

    const groupById = new Map(groups.map((group) => [group.duplicateId, group]));
    const allAssetIds = groups.flatMap((group) => group.assets.map((asset) => asset.id));
    const imagePaths = await this.aiDedupRepository.getImagePaths(ownerId, allAssetIds);
    const pathsByGroup = new Map<string, AiDedupImagePath[]>(
      groups.map((group) => {
        const memberIds = new Set(group.assets.map((asset) => asset.id));
        return [group.duplicateId, imagePaths.filter((path) => memberIds.has(path.assetId))];
      }),
    );

    const cacheKeys = new Map<string, string>(
      groups.map((group) => [
        group.duplicateId,
        buildAiDedupCacheKey({
          provider: config.provider,
          baseURL: config.baseURL,
          model: config.model,
          promptVersion: config.promptVersion,
          promptTemplate: config.prompt || AI_DEDUP_DEFAULT_PROMPT,
          strategyHint: config.strategyHint,
          keepCount: config.keepCount,
          maxImagesPerGroup: config.maxImagesPerGroup,
          maxImageDimension: config.maxImageDimension,
          imageQuality: config.imageQuality,
          temperature: config.temperature,
          maxTokens: config.maxTokens,
          memberHash: buildMemberHash(group.rawAssets, pathsByGroup.get(group.duplicateId) ?? []),
          ownerId,
          // [ai-dedup] The threshold decides needsManualReview and therefore the stored
          // recommendation set; it must invalidate stale cached recommendations.
          lowConfidenceThreshold: config.lowConfidenceThreshold,
        }),
      ]),
    );

    // [ai-dedup] Cache lookup BEFORE the quota/breaker gates: an exhausted quota or an open
    // breaker must never hide results that are already paid for and cached (E5).
    const cached = await this.aiDedupRepository.getByCacheKeys(
      ownerId,
      cacheKeys.values().toArray(),
      config.cacheTtlDays,
    );
    const cachedByKey = new Map(cached.map((row) => [row.cacheKey, row]));

    const results: AiDedupGroupResult[] = [];
    const pending: DuplicateGroup[] = [];
    for (const duplicateId of ids) {
      const group = groupById.get(duplicateId);
      if (!group) {
        results.push(
          buildDegradedResult(
            { duplicateId, assets: [], model: config.model, promptVersion: config.promptVersion },
            AiDedupErrorCode.NotFound,
          ),
        );
        continue;
      }

      const cacheKey = cacheKeys.get(duplicateId) as string;
      const hit = cachedByKey.get(cacheKey);
      const isUsable =
        hit !== undefined &&
        !dto.force &&
        hit.promptVersion === config.promptVersion &&
        hit.model === config.model &&
        (hit.degraded
          ? // [ai-dedup] Failure results are reused briefly so a broken model is not
            // re-billed on every page load; force=true still bypasses this.
            isFreshWithinMs(hit.createdAt, AI_DEDUP_DEGRADED_CACHE_TTL_MS)
          : isFresh(hit.createdAt, config.cacheTtlDays));

      if (isUsable && hit) {
        // Cache hit: zero external requests, zero billing (E5).
        results.push(hit.result);
      } else {
        pending.push(group);
      }
    }

    // [ai-dedup] Groups dropped by the `maxGroupsPerRequest` cap degrade explicitly
    // instead of silently vanishing from the response.
    const idSet = new Set(ids);
    const truncatedIds = dto.duplicateIds.filter((duplicateId) => !idSet.has(duplicateId));

    if (pending.length > 0) {
      // [ai-dedup] Quota and breaker guard ONLY the groups that would trigger real
      // external calls; already-cached results were returned above (E5: cache hits are free).
      const quotaExhausted = isQuotaExceeded(used, config.dailyCallLimitPerUser);
      const breakerBlocked = !this.breaker.canRequest();
      const capabilityCode = this.activeCapabilityFailure(config);
      if (capabilityCode) {
        // [ai-dedup] Zero external calls for a known-bad model configuration.
        results.push(
          ...pending.map((group) => buildDegradedResult(this.resultBase(group, config), capabilityCode)),
        );
      } else if (quotaExhausted || breakerBlocked) {
        if (quotaExhausted && config.autoDisableOnLimit) {
          this.breaker.forceOpen();
        }
        results.push(
          ...pending.map((group) => buildDegradedResult(this.resultBase(group, config), AiDedupErrorCode.QuotaExceeded)),
        );
      } else {
        if (config.maxConcurrency !== this.semaphoreMax) {
          this.semaphore = new Semaphore(config.maxConcurrency);
          this.semaphoreMax = config.maxConcurrency;
        }

        let credential: string | null = null;
        try {
          credential = await this.credentials.get();
        } catch {
          credential = null;
        }

        if (credential === null) {
          results.push(
            ...pending.map((group) => buildDegradedResult(this.resultBase(group, config), AiDedupErrorCode.NotConfigured)),
          );
        } else {
          // [ai-dedup] The per-group atomic quota reservation inside evaluateOne is the real
          // limit; this Promise.all can safely fan out to every pending group.
          const evaluated = await Promise.all(
            pending.map((group) =>
              this.semaphore.run(() =>
                this.evaluateOne(
                  auth,
                  group,
                  config,
                  credential as string,
                  cacheKeys.get(group.duplicateId) as string,
                  pathsByGroup.get(group.duplicateId) ?? [],
                ),
              ),
            ),
          );
          results.push(...evaluated);
        }
      }
    }

    for (const duplicateId of truncatedIds) {
      results.push(
        buildDegradedResult(
          { duplicateId, assets: [], model: config.model, promptVersion: config.promptVersion },
          AiDedupErrorCode.Truncated,
        ),
      );
    }

    const byId = new Map(results.map((result) => [result.duplicateId, result]));
    const ordered = [...ids, ...truncatedIds]
      .map((duplicateId) => byId.get(duplicateId))
      .filter((value): value is AiDedupGroupResult => !!value);
    return {
      results: ordered,
      degradedCount: ordered.filter((result) => result.degraded).length,
      truncatedCount: ordered.filter((result) => result.truncated).length,
      quota,
    };
  }

  /** Shared degraded-result base for a loaded group (keeps heuristic recommendations alive). */
  private resultBase(group: DuplicateGroup, config: AiDedupConfig) {
    return {
      duplicateId: group.duplicateId,
      assets: group.assets,
      model: config.model,
      promptVersion: config.promptVersion,
    };
  }

  private capabilityFingerprint(config: AiDedupConfig): string {
    return [config.baseURL, config.model, config.maxTokens, config.promptVersion].join('|');
  }

  private activeCapabilityFailure(config: AiDedupConfig): AiDedupErrorCode | null {
    const failure = this.capabilityFailure;
    if (!failure || failure.fingerprint !== this.capabilityFingerprint(config)) {
      return null;
    }
    return Date.now() - failure.at < 60_000 ? failure.code : null;
  }

  private markCapabilityFailure(config: AiDedupConfig, code: AiDedupErrorCode): void {
    if (code !== AiDedupErrorCode.OutputTruncated && code !== AiDedupErrorCode.ModelNoVision) {
      return;
    }
    this.logger.warn(`[ai-dedup] suppressing further external calls for this configuration: ${code}`);
    this.capabilityFailure = {
      fingerprint: this.capabilityFingerprint(config),
      at: Date.now(),
      code,
    };
  }

  /**
Static preconditions: enabled / configured / privacy / key / credential / SSRF.
Quota and breaker checks are deliberately NOT here — they are enforced per pending
group AFTER the cache lookup so cached results stay available (E5) and the real
limit is the atomic `tryConsumeCall` reservation inside `evaluateOne`.
*/
  private async checkStaticPreconditions(config: AiDedupConfig): Promise<AiDedupErrorCode | null> {
    if (!config.enabled) {
      return AiDedupErrorCode.NotEnabled;
    }
    if (!config.baseURL.trim() || !config.model.trim()) {
      return AiDedupErrorCode.NotConfigured;
    }
    if (!config.privacyAcknowledged) {
      return AiDedupErrorCode.NotConfigured;
    }
    if (!hasEncryptionKey()) {
      return AiDedupErrorCode.EncryptionKeyMissing;
    }
    if (!(await this.credentials.has())) {
      return AiDedupErrorCode.NotConfigured;
    }

    // Six-fold SSRF validation before any external request (§3.4.5).
    const ssrf = await validateBaseUrl(config.baseURL, config.allowedHosts);
    if (!ssrf.ok) {
      return AiDedupErrorCode.SsrfBlocked;
    }
    return null;
  }

  private async loadGroups(auth: AuthDto, ids: string[]): Promise<DuplicateGroup[]> {
    const wanted = new Set(ids);
    const all = await this.duplicateRepository.getAll(auth.user.id);
    return all
      .filter((group) => wanted.has(group.duplicateId))
      .map((group) => ({
        duplicateId: group.duplicateId,
        rawAssets: group.assets,
        assets: group.assets.map((asset) => mapAsset(asset, { auth })),
      }));
  }

  private async evaluateOne(
    auth: AuthDto,
    group: DuplicateGroup,
    config: AiDedupConfig,
    credential: string,
    cacheKey: string,
    paths: AiDedupImagePath[],
  ): Promise<AiDedupGroupResult> {
    const ownerId = auth.user.id;
    const base = {
      duplicateId: group.duplicateId,
      assets: group.assets,
      model: config.model,
      promptVersion: config.promptVersion || AI_DEDUP_PROMPT_VERSION,
    };
    let inputTokens = 0;
    let outputTokens = 0;
    let consumedQuota = false;

    try {
      // Q5: any non-image member degrades the whole group (no incomplete delete decisions).
      if (group.assets.some((asset) => asset.type !== AssetType.Image) || paths.length === 0) {
        return buildDegradedResult(base, AiDedupErrorCode.UnsupportedMediaType);
      }

      const prepared = await prepareImages(
        paths,
        {
          maxImagesPerGroup: config.maxImagesPerGroup,
          maxImageDimension: config.maxImageDimension,
          imageQuality: config.imageQuality,
        },
        cacheKey,
      );
      if (prepared.images.length === 0) {
        return buildDegradedResult(base, AiDedupErrorCode.UnsupportedMediaType);
      }

      const systemPrompt = renderPrompt(config.prompt || AI_DEDUP_DEFAULT_PROMPT, {
        assetCount: prepared.images.length,
        keepCount: Math.min(config.keepCount, prepared.images.length),
        strategyHint: config.strategyHint,
      });

      // [ai-dedup] Atomic quota reservation BEFORE the external call: one conditional
      // upsert closes the race where a request fans out N groups after a single
      // entry-time check (the old bypass could fire N calls with quota "remaining").
      consumedQuota = await this.aiDedupRepository.tryConsumeCall(ownerId, config.dailyCallLimitPerUser);
      if (!consumedQuota) {
        if (config.autoDisableOnLimit) {
          this.breaker.forceOpen();
        }
        this.logger.warn(`[ai-dedup] group ${group.duplicateId} degraded: quota exhausted`);
        return buildDegradedResult(base, AiDedupErrorCode.QuotaExceeded);
      }

      const raw = await this.provider.evaluate(
        {
          baseURL: config.baseURL,
          model: config.model,
          timeoutMs: config.timeoutMs,
          maxTokens: config.maxTokens,
          temperature: 0,
          allowedHosts: config.allowedHosts,
          systemPrompt,
          userPrompt: `本组共 ${prepared.images.length} 张照片，按编号 1..${prepared.images.length} 评估；请按系统提示输出一个合法 JSON 对象。`,
          images: prepared.images.map((image) => ({ index: image.index, base64Jpeg: image.base64Jpeg })),
        },
        credential,
      );
      inputTokens = raw.inputTokens;
      outputTokens = raw.outputTokens;

      const outcome = parseAndValidate(raw.content, {
        ...base,
        scoredAssetIds: prepared.images.map((image) => image.assetId),
        unscoredAssetIds: prepared.unscoredAssetIds,
        indexMap: prepared.indexMap,
        keepCount: config.keepCount,
        lowConfidenceThreshold: config.lowConfidenceThreshold,
        // A threshold of 0 disables the conservative low-confidence policy (Q12).
        lowConfidenceStrict: config.lowConfidenceThreshold > 0,
        strategyApplied: config.strategyHint.trim().length > 0,
        truncated: prepared.truncated,
      });

      if (!outcome.ok) {
        this.breaker.recordFailure();
        this.markCapabilityFailure(config, outcome.code);
        // [ai-dedup] Persist the failure briefly so the model is not re-billed on the
        // next page load; the short TTL reuse lives in the isUsable check above.
        const degraded = buildDegradedResult(base, outcome.code);
        await this.persistScore(ownerId, group, cacheKey, degraded, config, inputTokens, outputTokens);
        return degraded;
      }
      this.breaker.recordSuccess();

      await this.persistScore(ownerId, group, cacheKey, outcome.result, config, inputTokens, outputTokens);
      return outcome.result;
    } catch (error) {
      const code =
        error instanceof AiDedupProviderError ? error.code : AiDedupErrorCode.ProviderError;
      this.breaker.recordFailure();
      this.markCapabilityFailure(config, code);
      // Only the classification/category is logged: no apiKey, headers, images or response body.
      this.logger.warn(`[ai-dedup] group ${group.duplicateId} degraded: ${code}`);
      const degraded = buildDegradedResult(base, code);
      if (consumedQuota) {
        await this.persistScore(ownerId, group, cacheKey, degraded, config, inputTokens, outputTokens);
      }
      return degraded;
    } finally {
      if (consumedQuota) {
        // Token/cost accounting for a call whose quota slot was already reserved above.
        // Awaiting (instead of fire-and-forget) keeps the DB write inside the request lifetime;
        // a counter failure is logged but never turns a successful evaluation into an error.
        try {
          await this.aiDedupRepository.recordUsage(
            ownerId,
            inputTokens,
            outputTokens,
            estimateCost(inputTokens, outputTokens, config),
          );
        } catch (error) {
          this.logger.warn(`[ai-dedup] usage counter update failed: ${this.errorLabel(error)}`);
        }
      }
    }
  }

  /** Writes (or overwrites) the cached score for one group, clearing stale rows first. */
  private async persistScore(
    ownerId: string,
    group: DuplicateGroup,
    cacheKey: string,
    result: AiDedupGroupResult,
    config: AiDedupConfig,
    inputTokens: number,
    outputTokens: number,
  ): Promise<void> {
    try {
      // Remove every previous row for this group (member/config changes produce new keys;
      // without this the table grows without bound until the TTL lazily drops rows).
      await this.aiDedupRepository.deleteAllForGroup(ownerId, group.duplicateId);
      await this.aiDedupRepository.upsertScore({
        ownerId,
        duplicateId: group.duplicateId,
        cacheKey,
        result,
        promptVersion: result.promptVersion,
        model: config.model,
        degraded: result.degraded,
        inputTokens,
        outputTokens,
        estimatedCostUsd: estimateCost(inputTokens, outputTokens, config),
      });
    } catch (error) {
      // A cache write failure must never discard an already-computed evaluation.
      this.logger.warn(`[ai-dedup] score cache write failed: ${this.errorLabel(error)}`);
    }
  }

  private degradeAll(
    ids: string[],
    config: AiDedupConfig,
    code: AiDedupErrorCode,
    quota: { used: number; limit: number },
  ): AiDedupEvaluateResponse {
    return {
      results: ids.map((duplicateId) =>
        buildDegradedResult(
          { duplicateId, assets: [], model: config.model, promptVersion: config.promptVersion },
          code,
        ),
      ),
      degradedCount: ids.length,
      truncatedCount: 0,
      quota,
    };
  }

  private degradeGroups(
    groups: DuplicateGroup[],
    ids: string[],
    config: AiDedupConfig,
    code: AiDedupErrorCode,
    quota: { used: number; limit: number },
  ): AiDedupEvaluateResponse {
    const byId = new Map(groups.map((group) => [group.duplicateId, group]));
    return {
      results: ids.map((duplicateId) =>
        buildDegradedResult(
          {
            duplicateId,
            assets: byId.get(duplicateId)?.assets ?? [],
            model: config.model,
            promptVersion: config.promptVersion,
          },
          code,
        ),
      ),
      degradedCount: ids.length,
      truncatedCount: 0,
      quota,
    };
  }

  /** Error label for logs: never includes credential material or provider response bodies. */
  private errorLabel(error: unknown): string {
    if (error instanceof AiDedupProviderError) {
      return error.code;
    }
    return error instanceof Error ? error.name : 'UNKNOWN';
  }
}
