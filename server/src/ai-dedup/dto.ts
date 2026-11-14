import { createZodDto } from 'nestjs-zod';
import z from 'zod';

/**
Error / degradation codes for the AI dedup feature.
Defined here (NOT in `src/enum.ts`) so the module stays self-contained and removable.
*/
export enum AiDedupErrorCode {
  NotEnabled = 'NOT_ENABLED',
  NotConfigured = 'NOT_CONFIGURED',
  EncryptionKeyMissing = 'ENCRYPTION_KEY_MISSING',
  QuotaExceeded = 'QUOTA_EXCEEDED',
  Timeout = 'TIMEOUT',
  InvalidResponse = 'INVALID_RESPONSE',
  ProviderError = 'PROVIDER_ERROR',
  ModelNoVision = 'MODEL_NO_VISION',
  SsrfBlocked = 'SSRF_BLOCKED',
  UnsupportedMediaType = 'UNSUPPORTED_MEDIA_TYPE',
  LowConfidence = 'LOW_CONFIDENCE',
  NoPermission = 'NO_PERMISSION',
  NotFound = 'NOT_FOUND',
  PartialFailure = 'PARTIAL_FAILURE',
  /** [ai-dedup] The group was dropped by `maxGroupsPerRequest`; degraded explicitly instead of vanishing. */
  Truncated = 'TRUNCATED',
}

/**
Shuffled 1..N index (stringified JSON key) -> assetId. Kept server-side and persisted with
the result, never exposed to the vision model. `Record<string, string>` matches the
`z.record(z.string(), z.uuidv4())` DTO shape after JSON serialization.
*/
export type AiDedupIndexMap = Record<string, string>;

export const AiDedupTestReasonSchema = z.enum(['AUTH', 'TIMEOUT', 'NO_VISION', 'NETWORK', 'SSRF_BLOCKED', 'UNKNOWN']);

export const AiDedupScoresSchema = z
  .object({
    clarity: z.number().min(0).max(10).meta({ format: 'double' }),
    quality: z.number().min(0).max(10).meta({ format: 'double' }),
    composition: z.number().min(0).max(10).meta({ format: 'double' }),
  })
  .meta({ id: 'AiDedupScoresDto' });

/**
Per-asset score. `decision` / `deleteReason` / `scoreGapToBest` are v1.1 derived fields:
they are computed server-side from the ranked results, never returned by the model.
*/
export const AiDedupAssetScoreSchema = z
  .object({
    assetId: z.uuidv4().describe('Asset id'),
    index: z.int().min(1).describe('1-based shuffled index sent to the model'),
    scores: AiDedupScoresSchema,
    weightedScore: z.number().min(0).max(10).meta({ format: 'double' }),
    confidence: z.number().min(0).max(1).meta({ format: 'double' }),
    reason: z.string().max(40),
    defects: z.array(z.string()),
    recommendedKeep: z.boolean(),
    decision: z.enum(['keep', 'trash']),
    deleteReason: z.string().max(40),
    scoreGapToBest: z.number().min(0).max(10).meta({ format: 'double' }),
    source: z.enum(['ai', 'heuristic']),
  })
  .meta({ id: 'AiDedupAssetScoreDto' });

export const AiDedupGroupResultSchema = z
  .object({
    duplicateId: z.uuidv4().describe('Duplicate group id (existing asset.duplicateId semantics)'),
    recommendedKeepAssetIds: z.array(z.uuidv4()).describe('AI recommended keep set; empty when degraded'),
    results: z.array(AiDedupAssetScoreSchema),
    summary: z.string().max(60),
    strategyApplied: z.boolean(),
    promptVersion: z.string(),
    model: z.string(),
    generatedAt: z.string().describe('ISO 8601 UTC'),
    degraded: z.boolean(),
    degradeReason: z.string().nullable(),
    needsManualReview: z.boolean(),
    truncated: z.boolean(),
    indexMap: z.record(z.string(), z.uuidv4()).describe('Shuffled 1..N index -> assetId; never sent to the model'),
  })
  .meta({ id: 'AiDedupGroupResultDto' });

export const AiDedupQuotaSchema = z
  .object({ used: z.int().min(0), limit: z.int().min(0) })
  .meta({ id: 'AiDedupQuotaDto' });

export const AiDedupEvaluateSchema = z
  .object({
    duplicateIds: z.array(z.uuidv4()).min(1).max(100).describe('Duplicate group ids to evaluate'),
    force: z.boolean().default(false).describe('Bypass the score cache for these groups'),
  })
  .meta({ id: 'AiDedupEvaluateDto' });

export const AiDedupEvaluateResponseSchema = z
  .object({
    results: z.array(AiDedupGroupResultSchema),
    degradedCount: z.int().min(0),
    truncatedCount: z.int().min(0),
    quota: AiDedupQuotaSchema,
  })
  .meta({ id: 'AiDedupEvaluateResponseDto' });

export const AiDedupPromptDefaultsSchema = z
  .object({
    promptVersion: z.string(),
    strategyHint: z.string(),
    keepCount: z.int(),
    fallbackStrategy: z.string(),
    lowConfidenceThreshold: z.number().meta({ format: 'double' }),
    cacheTtlDays: z.int(),
  })
  .meta({ id: 'AiDedupPromptDefaultsDto' });

/**
E2 response. Deliberately minimal: no baseURL, model name, credential or per-user usage.
`trashEnabled` lets the confirmation dialog switch to the permanent-delete warning.
*/
export const AiDedupPromptSchema = z
  .object({
    enabled: z.boolean(),
    version: z.string(),
    strategySummary: z.string(),
    promptTemplate: z.string().describe('Full fixed prompt template (read-only)'),
    trashEnabled: z.boolean(),
    defaults: AiDedupPromptDefaultsSchema,
  })
  .meta({ id: 'AiDedupPromptDto' });

export const AiDedupCredentialSchema = z
  .object({ apiKey: z.string().min(1).max(4096) })
  .meta({ id: 'AiDedupCredentialDto' });

export const AiDedupCredentialStatusSchema = z
  .object({
    configured: z.boolean(),
    masked: z.string().describe('Masked apiKey, never the plaintext'),
    updatedAt: z.string(),
  })
  .meta({ id: 'AiDedupCredentialStatusDto' });

export const AiDedupClearResultSchema = z
  .object({ cleared: z.boolean() })
  .meta({ id: 'AiDedupClearResultDto' });

export const AiDedupDeleteScoresSchema = z
  .object({
    ownerId: z.uuidv4().optional(),
    includeUsage: z.boolean().default(true),
  })
  .meta({ id: 'AiDedupDeleteScoresDto' });

export const AiDedupPurgeResultSchema = z
  .object({
    scoresDeleted: z.int().min(0),
    usageDeleted: z.int().min(0),
    credentialCleared: z.boolean(),
  })
  .meta({ id: 'AiDedupPurgeResultDto' });

export const AiDedupTestConnectionSchema = z
  .object({
    baseURL: z.string().optional(),
    model: z.string().optional(),
    apiKey: z.string().optional(),
  })
  .meta({ id: 'AiDedupTestConnectionDto' });

export const AiDedupTestResultSchema = z
  .object({
    ok: z.boolean(),
    /** Optional (not nullable): a nullable enum makes the generated SDK emit an invalid member. */
    reason: AiDedupTestReasonSchema.optional(),
    latencyMs: z.int().min(0),
  })
  .meta({ id: 'AiDedupTestResultDto' });

export const AiDedupUsageQuerySchema = z
  .object({
    ownerId: z.uuidv4().optional(),
    month: z.string().regex(/^\d{4}-\d{2}$/).optional(),
  })
  .meta({ id: 'AiDedupUsageQueryDto' });

export const AiDedupUsageBucketSchema = z
  .object({
    calls: z.int().min(0),
    inputTokens: z.int().min(0),
    outputTokens: z.int().min(0),
    estimatedCostUsd: z.number().min(0).meta({ format: 'double' }),
  })
  .meta({ id: 'AiDedupUsageBucketDto' });

export const AiDedupOwnerUsageSchema = z
  .object({
    ownerId: z.uuidv4(),
    calls: z.int().min(0),
    inputTokens: z.int().min(0),
    outputTokens: z.int().min(0),
    estimatedCostUsd: z.number().min(0).meta({ format: 'double' }),
  })
  .meta({ id: 'AiDedupOwnerUsageDto' });

export const AiDedupUsageSchema = z
  .object({
    today: AiDedupUsageBucketSchema,
    month: AiDedupUsageBucketSchema,
    byOwner: z.array(AiDedupOwnerUsageSchema),
  })
  .meta({ id: 'AiDedupUsageDto' });

/**
Internal model response schema (technical design §3.6.1). The model output is parsed as
data only; the server never trusts its ordering and re-ranks everything.
*/
export const AiDedupModelResponseSchema = z
  .object({
    version: z.string(),
    strategyApplied: z.boolean(),
    results: z.array(
      z.object({
        index: z.int().min(1),
        scores: AiDedupScoresSchema,
        weightedScore: z.number().min(0).max(10).meta({ format: 'double' }),
        confidence: z.number().min(0).max(1).meta({ format: 'double' }),
        reason: z.string().max(40),
        defects: z.array(z.string()).default([]),
      }),
    ),
    recommendedKeepIndices: z.array(z.int().min(1)),
    summary: z.string().max(60),
  })
  .meta({ id: 'AiDedupModelResponseDto' });

export class AiDedupScoresDto extends createZodDto(AiDedupScoresSchema) {}
export class AiDedupAssetScoreDto extends createZodDto(AiDedupAssetScoreSchema) {}
export class AiDedupGroupResultDto extends createZodDto(AiDedupGroupResultSchema) {}
export class AiDedupQuotaDto extends createZodDto(AiDedupQuotaSchema) {}
export class AiDedupEvaluateDto extends createZodDto(AiDedupEvaluateSchema) {}
export class AiDedupEvaluateResponseDto extends createZodDto(AiDedupEvaluateResponseSchema) {}
export class AiDedupPromptDto extends createZodDto(AiDedupPromptSchema) {}
export class AiDedupCredentialDto extends createZodDto(AiDedupCredentialSchema) {}
export class AiDedupCredentialStatusDto extends createZodDto(AiDedupCredentialStatusSchema) {}
export class AiDedupClearResultDto extends createZodDto(AiDedupClearResultSchema) {}
export class AiDedupDeleteScoresDto extends createZodDto(AiDedupDeleteScoresSchema) {}
export class AiDedupPurgeResultDto extends createZodDto(AiDedupPurgeResultSchema) {}
export class AiDedupTestConnectionDto extends createZodDto(AiDedupTestConnectionSchema) {}
export class AiDedupTestResultDto extends createZodDto(AiDedupTestResultSchema) {}
export class AiDedupUsageQueryDto extends createZodDto(AiDedupUsageQuerySchema) {}
export class AiDedupUsageDto extends createZodDto(AiDedupUsageSchema) {}

export type AiDedupScores = z.infer<typeof AiDedupScoresSchema>;
export type AiDedupAssetScore = z.infer<typeof AiDedupAssetScoreSchema>;
export type AiDedupGroupResult = z.infer<typeof AiDedupGroupResultSchema>;
export type AiDedupEvaluateRequest = z.infer<typeof AiDedupEvaluateSchema>;
export type AiDedupEvaluateResponse = z.infer<typeof AiDedupEvaluateResponseSchema>;
export type AiDedupPrompt = z.infer<typeof AiDedupPromptSchema>;
export type AiDedupCredentialStatus = z.infer<typeof AiDedupCredentialStatusSchema>;
export type AiDedupClearResult = z.infer<typeof AiDedupClearResultSchema>;
export type AiDedupDeleteScoresRequest = z.infer<typeof AiDedupDeleteScoresSchema>;
export type AiDedupPurgeResult = z.infer<typeof AiDedupPurgeResultSchema>;
export type AiDedupTestConnectionRequest = z.infer<typeof AiDedupTestConnectionSchema>;
export type AiDedupTestResult = z.infer<typeof AiDedupTestResultSchema>;
export type AiDedupUsageQuery = z.infer<typeof AiDedupUsageQuerySchema>;
export type AiDedupUsageBucket = z.infer<typeof AiDedupUsageBucketSchema>;
export type AiDedupUsage = z.infer<typeof AiDedupUsageSchema>;
export type AiDedupModelResponse = z.infer<typeof AiDedupModelResponseSchema>;
