import { workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ImmichSettings } from 'data';

const DOMAIN = 0x0001;

/**
 * Registers a periodic "delayed work" that wakes the app to run a backup
 * session even when the app is not open. Registration follows the
 * automatic-backup setting and configured folders.
 */
export class BackupScheduler {
  private static readonly WORK_ID = 1001;
  private static readonly REPEAT_INTERVAL_MS = 2 * 60 * 60 * 1000;

  /** Re-register or unregister the periodic backup work from settings. */
  static sync(): void {
    const enabled: boolean = ImmichSettings.getBackupEnabled();
    const hasFolders: boolean = ImmichSettings.getBackupFolders().length > 0;
    hilog.info(DOMAIN, 'ImmichBackup', 'sync enabled=%{public}s folders=%{public}s',
      enabled ? 'true' : 'false', hasFolders ? 'true' : 'false');
    if (enabled && hasFolders) {
      BackupScheduler.enable();
    } else {
      BackupScheduler.disable();
    }
  }

  /** Register the periodic backup work (best-effort). */
  static enable(): void {
    // Re-registering an existing workId fails with 9700005, so stop first.
    try {
      workScheduler.stopWork(BackupScheduler.buildWork());
    } catch (err) {
      // not registered yet
    }
    try {
      workScheduler.startWork(BackupScheduler.buildWork());
      hilog.info(DOMAIN, 'ImmichBackup', 'startWork submitted');
    } catch (err) {
      hilog.error(DOMAIN, 'ImmichBackup', 'startWork failed: %{public}s', JSON.stringify(err));
    }
  }

  /** Unregister the periodic backup work (best-effort). */
  static disable(): void {
    try {
      workScheduler.stopWork(BackupScheduler.buildWork());
      hilog.info(DOMAIN, 'ImmichBackup', 'stopWork submitted');
    } catch (err) {
      hilog.error(DOMAIN, 'ImmichBackup', 'stopWork failed: %{public}s', JSON.stringify(err));
    }
  }

  /** The full WorkInfo shared by start/stop so conditions always match. */
  private static buildWork(): workScheduler.WorkInfo {
    const work: workScheduler.WorkInfo = {
      workId: BackupScheduler.WORK_ID,
      bundleName: 'app.yyzh999.immich',
      abilityName: 'BackupWorkScheduler',
      isPersisted: true,
      networkType: workScheduler.NetworkType.NETWORK_TYPE_ANY,
      isRepeat: true,
      repeatCycleTime: BackupScheduler.REPEAT_INTERVAL_MS
    };
    return work;
  }
}
