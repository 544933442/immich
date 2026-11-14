import {
  Column,
  ForeignKeyColumn,
  PrimaryColumn,
  Table,
  UpdateDateColumn,
  type Generated,
  type Timestamp,
} from '@immich/sql-tools';
import { UserTable } from 'src/schema/tables/user.table.js';

/** Per-owner, per-day usage counters. Written with a single atomic ON CONFLICT upsert. */
@Table('ai_dedup_usage')
export class AiDedupUsageTable {
  @ForeignKeyColumn(() => UserTable, {
    onDelete: 'CASCADE',
    onUpdate: 'CASCADE',
    primary: true,
    index: false,
  })
  ownerId!: string;

  @PrimaryColumn({ type: 'date' })
  date!: Timestamp;

  @Column({ type: 'integer', default: 0 })
  calls!: Generated<number>;

  @Column({ type: 'integer', default: 0 })
  inputTokens!: Generated<number>;

  @Column({ type: 'integer', default: 0 })
  outputTokens!: Generated<number>;

  @Column({ type: 'double precision', default: 0 })
  estimatedCostUsd!: Generated<number>;

  @UpdateDateColumn()
  updatedAt!: Generated<Timestamp>;
}
