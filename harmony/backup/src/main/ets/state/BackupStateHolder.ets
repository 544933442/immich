/**
 * Observable backup progress shared across pages, watched by V2 components.
 */
@ObservedV2
export class BackupStateHolder {
  /** Overall backup session state. */
  @Trace running: boolean = false;
  @Trace phase: string = 'idle';
  /** Current file being uploaded. */
  @Trace currentFile: string = '';
  /** Bytes sent / total for the current file. */
  @Trace progressSent: number = 0;
  @Trace progressTotal: number = 0;
  /** Session counters. */
  @Trace totalCount: number = 0;
  @Trace doneCount: number = 0;
  @Trace failedCount: number = 0;
  /** Last completed scan total, for UI display. */
  @Trace pendingCount: number = 0;
  @Trace lastError: string = '';
}

/** Process-wide backup state singleton. */
export const backupState: BackupStateHolder = new BackupStateHolder();
