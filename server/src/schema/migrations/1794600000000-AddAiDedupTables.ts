import { Kysely, sql } from 'kysely';

/**
Reversible schema for the AI dedup module. Column names/types/defaults and index names
mirror `schema/tables/ai-dedup-*.table.ts` so `mise run sql` and `migrations:generate`
report no drift. down() drops the usage table first (owner FK then score).
*/
export async function up(db: Kysely<any>): Promise<void> {
  await sql`CREATE TABLE "ai_dedup_score" (
  "id" uuid NOT NULL DEFAULT immich_uuid_v7(),
  "ownerId" uuid NOT NULL,
  "duplicateId" uuid NOT NULL,
  "cacheKey" character varying(64) NOT NULL,
  "result" jsonb NOT NULL,
  "promptVersion" character varying(32) NOT NULL,
  "model" character varying(128) NOT NULL,
  "degraded" boolean NOT NULL DEFAULT false,
  "inputTokens" integer NOT NULL DEFAULT 0,
  "outputTokens" integer NOT NULL DEFAULT 0,
  "estimatedCostUsd" double precision NOT NULL DEFAULT 0,
  "createdAt" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_dedup_score_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "ai_dedup_score_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE
);`.execute(db);

  await sql`CREATE UNIQUE INDEX "UQ_ai_dedup_score_cacheKey" ON "ai_dedup_score" ("cacheKey");`.execute(db);
  await sql`CREATE INDEX "IDX_ai_dedup_score_owner_group" ON "ai_dedup_score" ("ownerId", "duplicateId", "createdAt");`.execute(
    db,
  );
  await sql`CREATE INDEX "IDX_ai_dedup_score_createdAt" ON "ai_dedup_score" ("createdAt");`.execute(db);

  await sql`CREATE TABLE "ai_dedup_usage" (
  "ownerId" uuid NOT NULL,
  "date" date NOT NULL,
  "calls" integer NOT NULL DEFAULT 0,
  "inputTokens" integer NOT NULL DEFAULT 0,
  "outputTokens" integer NOT NULL DEFAULT 0,
  "estimatedCostUsd" double precision NOT NULL DEFAULT 0,
  "updatedAt" timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT "ai_dedup_usage_pkey" PRIMARY KEY ("ownerId", "date"),
  CONSTRAINT "ai_dedup_usage_ownerId_fkey" FOREIGN KEY ("ownerId") REFERENCES "user" ("id") ON UPDATE CASCADE ON DELETE CASCADE
);`.execute(db);
}

export async function down(db: Kysely<any>): Promise<void> {
  await sql`DROP TABLE IF EXISTS "ai_dedup_usage";`.execute(db);
  await sql`DROP TABLE IF EXISTS "ai_dedup_score";`.execute(db);
}
