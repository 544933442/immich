import { WorkSchedulerExtensionAbility, workScheduler } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppRuntime } from '../runtime/AppRuntime';

const DOMAIN = 0x0001;

/**
 * Delayed-work callback: wakes the process to run one backup session.
 * If the app was not running, AppRuntime is initialized with the
 * extension context first (notification permission dialogs are skipped
 * because no UIAbility is loaded).
 */
export default class BackupWorkSchedulerExtension extends WorkSchedulerExtensionAbility {
  onWorkStart(work: workScheduler.WorkInfo): void {
    hilog.info(DOMAIN, 'ImmichBackup', 'scheduled backup work starting');
    AppRuntime.init(this.context)
      .then((): Promise<void> => AppRuntime.runBackup())
      .then((): void => {
        hilog.info(DOMAIN, 'ImmichBackup', 'scheduled backup work finished');
      })
      .catch((err: Error): void => {
        hilog.error(DOMAIN, 'ImmichBackup', 'scheduled backup failed: %{public}s', err.message);
      });
  }

  onWorkStop(work: workScheduler.WorkInfo): void {
  }
}
