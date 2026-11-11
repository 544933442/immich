import { notificationManager } from '@kit.NotificationKit';
import { common } from '@kit.AbilityKit';
import { i18n } from '@kit.LocalizationKit';

/**
 * Publishes backup progress as a system notification so the user can follow
 * a running backup outside the app. Notification posting is best-effort:
 * if the user declines the permission, backup continues silently.
 */
export class ImmichBackupNotifier {
  private static readonly NOTIFY_ID = 1001;
  private static readonly NOTIFY_DONE_ID = 1002;
  private static enabled: boolean = false;

  static async requestPermission(context: common.UIAbilityContext): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(context);
      ImmichBackupNotifier.enabled = true;
    } catch (err) {
      ImmichBackupNotifier.enabled = false;
    }
  }

  static isEnabled(): boolean {
    return ImmichBackupNotifier.enabled;
  }

  static publishScanProgress(): void {
    if (!ImmichBackupNotifier.enabled) {
      return;
    }
    const isChinese: boolean = i18n.System.getAppPreferredLanguage().startsWith('zh');
    ImmichBackupNotifier.publish(
      isChinese ? '正在备份照片' : 'Backing up photos',
      isChinese ? '正在扫描本地文件夹…' : 'Scanning local folders…',
      ImmichBackupNotifier.NOTIFY_ID);
  }

  static publishUploadProgress(done: number, total: number, failed: number): void {
    if (!ImmichBackupNotifier.enabled) {
      return;
    }
    const isChinese: boolean = i18n.System.getAppPreferredLanguage().startsWith('zh');
    let text: string = isChinese ? `已上传 ${done}/${total}` : `Uploaded ${done}/${total}`;
    if (failed > 0) {
      text += isChinese ? `，失败 ${failed}` : `, ${failed} failed`;
    }
    ImmichBackupNotifier.publish(
      isChinese ? '正在备份照片' : 'Backing up photos', text, ImmichBackupNotifier.NOTIFY_ID);
  }

  static publishDone(done: number, total: number, failed: number): void {
    if (!ImmichBackupNotifier.enabled) {
      return;
    }
    const isChinese: boolean = i18n.System.getAppPreferredLanguage().startsWith('zh');
    let text: string = isChinese ? `已完成 ${done}/${total}` : `Completed ${done}/${total}`;
    if (failed > 0) {
      text += isChinese ? `，失败 ${failed}` : `, ${failed} failed`;
    }
    ImmichBackupNotifier.cancel();
    ImmichBackupNotifier.publish(
      isChinese ? '备份完成' : 'Backup completed', text, ImmichBackupNotifier.NOTIFY_DONE_ID);
  }

  static cancel(): void {
    if (!ImmichBackupNotifier.enabled) {
      return;
    }
    notificationManager.cancel(ImmichBackupNotifier.NOTIFY_ID).catch((): void => {
    });
  }

  private static publish(title: string, text: string, id: number): void {
    const request: notificationManager.NotificationRequest = {
      id: id,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: title,
          text: text
        }
      }
    };
    notificationManager.publish(request).catch((): void => {
    });
  }
}
