import {
  Column,
  CreateDateColumn,
  ForeignKeyColumn,
  Index,
  Table,
  type Generated,
  type Timestamp,
} from '@immich/sql-tools';
import { PrimaryGeneratedUuidV7Column } from 'src/decorators.js';
import { UserTable } from 'src/schema/tables/user.table.js';

/**
One row per duplicate group per cache key. `result` is the full AiDedupGroupResult JSONB.
`ownerId` cascades from user(id); `duplicateId` is a logical value with NO foreign key to
asset, so dismissing a group never corrupts audit data.
*/
@Table('ai_dedup_score')
@Index({ name: 'UQ_ai_dedup_score_cacheKey', columns: ['cacheKey'], unique: true })
@Index({ name: 'IDX_ai_dedup_score_owner_group', columns: ['ownerId', 'duplicateId', 'createdAt'] })
@Index({ name: 'IDX_ai_dedup_score_createdAt', columns: ['createdAt'] })
export class AiDedupScoreTable {
  // Matches `DEFAULT immich_uuid_v7()` in the migration (PrimaryGeneratedColumn would
  // generate `uuid_generate_v4()` and cause schema drift).
  @PrimaryGeneratedUuidV7Column()
  id!: Generated<string>;

  @ForeignKeyColumn(() => UserTable, { onDelete: 'CASCADE', onUpdate: 'CASCADE', index: false })
  ownerId!: string;

  @Column({ type: 'uuid' })
  duplicateId!: string;

  @Column({ type: 'character varying', length: 64 })
  cacheKey!: string;

  @Column({ type: 'jsonb' })
  result!: unknown;

  @Column({ type: 'character varying', length: 32 })
  promptVersion!: string;

  @Column({ type: 'character varying', length: 128 })
  model!: string;

  @Column({ type: 'boolean', default: false })
  degraded!: Generated<boolean>;

  @Column({ type: 'integer', default: 0 })
  inputTokens!: Generated<number>;

  @Column({ type: 'integer', default: 0 })
  outputTokens!: Generated<number>;

  @Column({ type: 'double precision', default: 0 })
  estimatedCostUsd!: Generated<number>;

  @CreateDateColumn()
  createdAt!: Generated<Timestamp>;
}
