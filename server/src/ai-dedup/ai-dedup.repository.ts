import { Injectable } from '@nestjs/common';
import { sql, type Kysely } from 'kysely';
import { InjectKysely } from 'nestjs-kysely';
import { DummyValue, GenerateSql } from 'src/decorators.js';
import { AssetFileType, AssetType } from 'src/enum.js';
import { DB } from 'src/schema/index.js';
import type { AiDedupGroupResult, AiDedupUsage, AiDedupUsageBucket } from 'src/ai-dedup/dto.js';
import type { AiDedupImagePath } from 'src/ai-dedup/image.js';

export interface AiDedupCachedScore {
  cacheKey: string;
  duplicateId: string;
  result: AiDedupGroupResult;
  promptVersion: string;
  model: string;
  degraded: boolean;
  createdAt: Date;
}

export interface AiDedupScoreWrite {
  ownerId: string;
  duplicateId: string;
  cacheKey: string;
  result: AiDedupGroupResult;
  promptVersion: string;
  model: string;
  degraded: boolean;
  inputTokens: number;
  outputTokens: number;
  estimatedCostUsd: number;
}

interface BucketRow {
  calls: string | number;
  inputTokens: string | number;
  outputTokens: string | number;
  estimatedCostUsd: string | number;
}

const emptyBucket = (): AiDedupUsageBucket => ({
  calls: 0,
  inputTokens: 0,
  outputTokens: 0,
  estimatedCostUsd: 0,
});

const toNumber = (value: string | number | undefined = 0): number => Number(value);

@Injectable()
export class AiDedupRepository {
  constructor(@InjectKysely() private db: Kysely<DB>) {}

  /** Batch cache lookup with lazy TTL. All rows are owner-scoped. */
  @GenerateSql({ params: [DummyValue.UUID, [DummyValue.STRING], 30] })
  async getByCacheKeys(ownerId: string, cacheKeys: string[], ttlDays: number): Promise<AiDedupCachedScore[]> {
    if (cacheKeys.length === 0) {
      return [];
    }

    const rows = await this.db
      .selectFrom('ai_dedup_score')
      .select(['cacheKey', 'duplicateId', 'result', 'promptVersion', 'model', 'degraded', 'createdAt'])
      .where('ownerId', '=', ownerId)
      .where('cacheKey', 'in', cacheKeys)
      .where(sql<boolean>`"createdAt" > now() - make_interval(days => ${ttlDays})`)
      .execute();

    return rows.map((row) => ({
      cacheKey: row.cacheKey,
      duplicateId: row.duplicateId,
      result: row.result as AiDedupGroupResult,
      promptVersion: row.promptVersion,
      model: row.model,
      degraded: row.degraded,
      createdAt: new Date(String(row.createdAt)),
    }));
  }

  /** Single-row upsert keyed by cacheKey (no write races between concurrent evaluations). */
  @GenerateSql({
    params: [
      {
        ownerId: DummyValue.UUID,
        duplicateId: DummyValue.UUID,
        cacheKey: DummyValue.STRING,
        result: {},
        promptVersion: DummyValue.STRING,
        model: DummyValue.STRING,
        degraded: false,
        inputTokens: 10,
        outputTokens: 20,
        estimatedCostUsd: 0.01,
      },
    ],
  })
  async upsertScore(write: AiDedupScoreWrite): Promise<void> {
    const values = {
      ownerId: write.ownerId,
      duplicateId: write.duplicateId,
      cacheKey: write.cacheKey,
      result: write.result as unknown,
      promptVersion: write.promptVersion,
      model: write.model,
      degraded: write.degraded,
      inputTokens: write.inputTokens,
      outputTokens: write.outputTokens,
      estimatedCostUsd: write.estimatedCostUsd,
    };

    await this.db
      .insertInto('ai_dedup_score')
      .values(values)
      .onConflict((oc) =>
        oc.columns(['cacheKey']).doUpdateSet({
          result: values.result,
          promptVersion: values.promptVersion,
          model: values.model,
          degraded: values.degraded,
          inputTokens: values.inputTokens,
          outputTokens: values.outputTokens,
          estimatedCostUsd: values.estimatedCostUsd,
          createdAt: sql`now()`,
        }),
      )
      .execute();
  }

  /** Deletes every cached row for one group (any cache key), executed just before writing a fresh score. */
  @GenerateSql({ params: [DummyValue.UUID, DummyValue.UUID] })
  async deleteAllForGroup(ownerId: string, duplicateId: string): Promise<void> {
    await this.db
      .deleteFrom('ai_dedup_score')
      .where('ownerId', '=', ownerId)
      .where('duplicateId', '=', duplicateId)
      .execute();
  }

  /**
Atomic quota reservation: increments today's `calls` only while it is below `limit`,
returning false when the quota is exhausted. A single conditional upsert closes the
read-then-write race between concurrent evaluations (previously the quota was read once
per request, so a single request with N pending groups could fire N external calls).
*/
  @GenerateSql({ params: [DummyValue.UUID, 200] })
  async tryConsumeCall(ownerId: string, limit: number): Promise<boolean> {
    const result = await sql<{ calls: string | number }>`
      INSERT INTO "ai_dedup_usage" ("ownerId", "date", "calls", "inputTokens", "outputTokens", "estimatedCostUsd", "updatedAt")
      VALUES (${ownerId}, CURRENT_DATE, 1, 0, 0, 0, now())
      ON CONFLICT ("ownerId", "date") DO UPDATE SET
        "calls" = "ai_dedup_usage"."calls" + 1,
        "updatedAt" = now()
      WHERE "ai_dedup_usage"."calls" < ${limit}
      RETURNING "calls"
    `.execute(this.db);
    return result.rows.length > 0;
  }

  /** Token/cost accounting for a call whose quota slot was already consumed by `tryConsumeCall`. */
  @GenerateSql({ params: [DummyValue.UUID, 100, 50, 0.01] })
  async recordUsage(ownerId: string, inputTokens: number, outputTokens: number, cost: number): Promise<void> {
    await sql`
      INSERT INTO "ai_dedup_usage" ("ownerId", "date", "calls", "inputTokens", "outputTokens", "estimatedCostUsd", "updatedAt")
      VALUES (${ownerId}, CURRENT_DATE, 0, ${inputTokens}, ${outputTokens}, ${cost}, now())
      ON CONFLICT ("ownerId", "date") DO UPDATE SET
        "inputTokens" = "ai_dedup_usage"."inputTokens" + EXCLUDED."inputTokens",
        "outputTokens" = "ai_dedup_usage"."outputTokens" + EXCLUDED."outputTokens",
        "estimatedCostUsd" = "ai_dedup_usage"."estimatedCostUsd" + EXCLUDED."estimatedCostUsd",
        "updatedAt" = now()
    `.execute(this.db);
  }

  @GenerateSql({ params: [DummyValue.UUID] })
  async getTodayUsage(ownerId: string): Promise<number> {
    const result = await sql<{ total: string }>`
      SELECT COALESCE(SUM("calls"), 0) AS "total"
      FROM "ai_dedup_usage"
      WHERE "ownerId" = ${ownerId} AND "date" = CURRENT_DATE
    `.execute(this.db);
    return toNumber(result.rows[0]?.total);
  }

  @GenerateSql({ params: [DummyValue.UUID, '2026-11'] })
  async getUsage(ownerId: string | undefined, month: string | undefined): Promise<AiDedupUsage> {
    const ownerFilter = ownerId ? sql`AND "ownerId" = ${ownerId}` : sql``;
    const selectedMonth = month ?? new Date().toISOString().slice(0, 7);

    const todayResult = await sql<BucketRow>`
      SELECT COALESCE(SUM("calls"), 0) AS "calls",
             COALESCE(SUM("inputTokens"), 0) AS "inputTokens",
             COALESCE(SUM("outputTokens"), 0) AS "outputTokens",
             COALESCE(SUM("estimatedCostUsd"), 0) AS "estimatedCostUsd"
      FROM "ai_dedup_usage"
      WHERE "date" = CURRENT_DATE ${ownerFilter}
    `.execute(this.db);

    const monthResult = await sql<BucketRow>`
      SELECT COALESCE(SUM("calls"), 0) AS "calls",
             COALESCE(SUM("inputTokens"), 0) AS "inputTokens",
             COALESCE(SUM("outputTokens"), 0) AS "outputTokens",
             COALESCE(SUM("estimatedCostUsd"), 0) AS "estimatedCostUsd"
      FROM "ai_dedup_usage"
      WHERE to_char("date", 'YYYY-MM') = ${selectedMonth} ${ownerFilter}
    `.execute(this.db);

    const byOwnerResult = await sql<BucketRow & { ownerId: string }>`
      SELECT "ownerId",
             COALESCE(SUM("calls"), 0) AS "calls",
             COALESCE(SUM("inputTokens"), 0) AS "inputTokens",
             COALESCE(SUM("outputTokens"), 0) AS "outputTokens",
             COALESCE(SUM("estimatedCostUsd"), 0) AS "estimatedCostUsd"
      FROM "ai_dedup_usage"
      WHERE to_char("date", 'YYYY-MM') = ${selectedMonth} ${ownerFilter}
      GROUP BY "ownerId"
    `.execute(this.db);

    const toBucket = (row: BucketRow | undefined): AiDedupUsageBucket =>
      row
        ? {
            calls: toNumber(row.calls),
            inputTokens: toNumber(row.inputTokens),
            outputTokens: toNumber(row.outputTokens),
            estimatedCostUsd: toNumber(row.estimatedCostUsd),
          }
        : emptyBucket();

    return {
      today: toBucket(todayResult.rows[0]),
      month: toBucket(monthResult.rows[0]),
      byOwner: byOwnerResult.rows.map((row) => ({ ownerId: row.ownerId, ...toBucket(row) })),
    };
  }

  /** "Clear all AI data": delete scores and (optionally) usage, always owner-scoped. */
  @GenerateSql({ params: [DummyValue.UUID, true] })
  async purge(
    ownerId: string | undefined,
    includeUsage: boolean,
  ): Promise<{ scoresDeleted: number; usageDeleted: number }> {
    const scoreQuery = this.db.deleteFrom('ai_dedup_score');
    const [scoreResult] = await (ownerId
      ? scoreQuery.where('ownerId', '=', ownerId)
      : scoreQuery
    ).execute();

    let usageDeleted = 0;
    if (includeUsage) {
      const usageQuery = this.db.deleteFrom('ai_dedup_usage');
      const [usageResult] = await (ownerId
        ? usageQuery.where('ownerId', '=', ownerId)
        : usageQuery
      ).execute();
      usageDeleted = Number(usageResult?.numDeletedRows ?? 0);
    }

    return { scoresDeleted: Number(scoreResult?.numDeletedRows ?? 0), usageDeleted };
  }

  /** Preview/thumbnail paths for IMAGE assets only, strictly owner-filtered. */
  @GenerateSql({ params: [DummyValue.UUID, [DummyValue.UUID]] })
  async getImagePaths(ownerId: string, assetIds: string[]): Promise<AiDedupImagePath[]> {
    if (assetIds.length === 0) {
      return [];
    }

    const rows = await this.db
      .selectFrom('asset_file')
      .innerJoin('asset', 'asset.id', 'asset_file.assetId')
      .select(['asset_file.assetId', 'asset_file.path', 'asset_file.type', 'asset_file.updateId'])
      .where('asset.ownerId', '=', ownerId)
      .where('asset.id', 'in', assetIds)
      .where('asset.type', '=', AssetType.Image)
      .where('asset.deletedAt', 'is', null)
      .where('asset_file.isEdited', '=', false)
      .where('asset_file.type', 'in', [AssetFileType.Preview, AssetFileType.Thumbnail])
      .execute();

    return rows.map((row) => ({
      assetId: row.assetId,
      path: row.path,
      type: row.type,
      updateId: row.updateId ?? null,
    }));
  }
}
