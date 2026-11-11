import { fileShare, picker } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackupFolderRecord, ImmichSettings } from 'data';
import { BackupScheduler, backupState } from 'backup';
import { AppRuntime } from '../../runtime/AppRuntime';

/**
 * Backup tab: manage persisted backup folders and drive the backup engine.
 */
@ComponentV2
export struct BackupPage {
  @Local folders: BackupFolderRecord[] = [];
  @Local autoBackup: boolean = false;
  @Local pendingCount: number = 0;
  @Local lastError: string = '';
  @Local picking: boolean = false;

  aboutToAppear(): void {
    this.refreshUi();
  }

  build() {
    Column() {
      Text($r('app.string.tab_backup'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.immich_text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Column({ space: 8 }) {
        Row({ space: 8 }) {
          Column({ space: 2 }) {
            Text($r('app.string.backup_auto'))
              .fontSize(15)
              .fontColor($r('app.color.immich_text_primary'))
            Text($r('app.string.backup_auto_desc'))
              .fontSize(12)
              .fontColor($r('app.color.immich_text_secondary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.autoBackup })
            .onChange((isOn: boolean) => {
              this.autoBackup = isOn;
              ImmichSettings.setBackupEnabled(isOn);
              BackupScheduler.sync();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding(14)
      .backgroundColor($r('app.color.immich_surface'))
      .borderRadius(14)
      .margin({ left: 12, right: 12 })

      Column({ space: 6 }) {
        Text($r('app.string.backup_folders_title'))
          .fontSize(13)
          .fontColor($r('app.color.immich_text_secondary'))
          .width('100%')
          .padding({ left: 16, top: 12 })
        if (this.folders.length === 0) {
          Text($r('app.string.backup_empty_hint'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 12 })
        } else {
          ForEach(this.folders, (folder: BackupFolderRecord) => {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(folder.name)
                  .fontSize(15)
                  .fontColor($r('app.color.immich_text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(folder.uri)
                  .fontSize(11)
                  .fontColor($r('app.color.immich_text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Image($r('app.media.ic_close'))
                .width(16)
                .height(16)
                .fillColor($r('app.color.immich_text_secondary'))
                .padding(10)
                .onClick(() => {
                  this.removeFolder(folder);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 8, top: 10, bottom: 10 })
            Divider().color($r('app.color.immich_outline')).margin({ left: 16 })
          }, (folder: BackupFolderRecord) => folder.uri)
        }
        Button($r('app.string.backup_add_folder'))
          .buttonStyle(ButtonStyleMode.NORMAL)
          .backgroundColor($r('app.color.immich_surface'))
          .fontColor($r('app.color.immich_primary'))
          .width('100%')
          .height(44)
          .margin({ left: 12, right: 12, top: 6, bottom: 12 })
          .enabled(!this.picking)
          .onClick(() => {
            this.pickFolder();
          })
      }
      .width('100%')
      .backgroundColor($r('app.color.immich_surface'))
      .borderRadius(14)
      .margin({ left: 12, right: 12, top: 12 })

      Column({ space: 8 }) {
        if (backupState.running) {
          Text(backupState.phase === 'scanning' ?
            $r('app.string.backup_status_scanning') : $r('app.string.backup_status_uploading'))
            .fontSize(14)
            .fontColor($r('app.color.immich_text_primary'))
          if (backupState.phase === 'uploading' && backupState.currentFile.length > 0) {
            Text(`${backupState.currentFile} (${backupState.doneCount}/${backupState.totalCount})`)
              .fontSize(12)
              .fontColor($r('app.color.immich_text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: '90%' })
            if (backupState.progressTotal > 0) {
              Progress({ value: backupState.progressSent, total: backupState.progressTotal })
                .color($r('app.color.immich_primary'))
                .width('90%')
                .height(6)
            }
          }
          if (backupState.failedCount > 0) {
            Text(`${this.loadString('backup_failed_count')}: ${backupState.failedCount}`)
              .fontSize(12)
              .fontColor($r('app.color.immich_error'))
          }
        } else {
          Text(`${this.loadString('backup_pending')}: ${backupState.pendingCount}`)
            .fontSize(14)
            .fontColor($r('app.color.immich_text_secondary'))
          if (backupState.failedCount > 0) {
            Text(`${this.loadString('backup_failed_count')}: ${backupState.failedCount}`)
              .fontSize(12)
              .fontColor($r('app.color.immich_error'))
          }
        }
        if (this.lastError.length > 0) {
          Text(this.lastError)
            .fontSize(12)
            .fontColor($r('app.color.immich_error'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: '90%' })
        }
        Button(backupState.running ? $r('app.string.backup_stop') : $r('app.string.backup_now'))
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .backgroundColor(backupState.running ? $r('app.color.immich_error') : $r('app.color.immich_primary'))
          .fontColor(Color.White)
          .width('90%')
          .height(44)
          .margin({ top: 4 })
          .enabled(this.folders.length > 0)
          .onClick(() => {
            if (backupState.running) {
              AppRuntime.getEngine().cancel();
            } else {
              this.startBackup();
            }
          })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  private refreshUi(): void {
    this.folders = ImmichSettings.getBackupFolders();
    this.autoBackup = ImmichSettings.getBackupEnabled();
    this.lastError = backupState.lastError;
  }

  private async pickFolder(): Promise<void> {
    if (this.picking) {
      return;
    }
    this.picking = true;
    try {
      const documentPicker: picker.DocumentViewPicker =
        new picker.DocumentViewPicker(AppRuntime.getContext());
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.selectMode = picker.DocumentSelectMode.FOLDER;
      const uris: Array<string> = await documentPicker.select(options);
      hilog.info(0x0001, 'ImmichBackup', 'picker returned %{public}d uris', uris.length);
      if (uris.length === 0) {
        return;
      }
      const uri: string = uris[0];
      hilog.info(0x0001, 'ImmichBackup', 'picked uri=%{public}s', uri);
      const policy: fileShare.PolicyInfo = {
        uri: uri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      const policies: Array<fileShare.PolicyInfo> = [policy];
      await fileShare.persistPermission(policies);
      hilog.info(0x0001, 'ImmichBackup', 'persistPermission ok');
      const folder: BackupFolderRecord = new BackupFolderRecord();
      folder.uri = uri;
      folder.name = this.folderNameOf(uri);
      const current: BackupFolderRecord[] = ImmichSettings.getBackupFolders();
      let exists: boolean = false;
      for (const item of current) {
        if (item.uri === uri) {
          exists = true;
        }
      }
      if (!exists) {
        current.push(folder);
        ImmichSettings.setBackupFolders(current);
      }
      hilog.info(0x0001, 'ImmichBackup', 'folders saved count=%{public}d',
        ImmichSettings.getBackupFolders().length);
      this.folders = ImmichSettings.getBackupFolders();
      BackupScheduler.sync();
      AppRuntime.getEngine().refreshPending().catch((err: Error): void => {
      });
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      this.lastError = error.message;
    } finally {
      this.picking = false;
    }
  }

  private async removeFolder(folder: BackupFolderRecord): Promise<void> {
    try {
      const policy: fileShare.PolicyInfo = {
        uri: folder.uri,
        operationMode: fileShare.OperationMode.READ_MODE
      };
      const policies: Array<fileShare.PolicyInfo> = [policy];
      await fileShare.revokePermission(policies);
    } catch (err) {
      // permission may already be released
    }
    const current: BackupFolderRecord[] = ImmichSettings.getBackupFolders();
    const remaining: BackupFolderRecord[] = [];
    for (const item of current) {
      if (item.uri !== folder.uri) {
        remaining.push(item);
      }
    }
    ImmichSettings.setBackupFolders(remaining);
    this.folders = remaining;
    BackupScheduler.sync();
    AppRuntime.getEngine().refreshPending().catch((err: Error): void => {
    });
  }

  private async startBackup(): Promise<void> {
    this.lastError = '';
    try {
      await AppRuntime.runBackup();
    } catch (err) {
      const message: string = err instanceof Error ? err.message : 'backup failed';
      this.lastError = message;
    }
    this.refreshUi();
  }

  private folderNameOf(uri: string): string {
    const parts: string[] = uri.split('/');
    const last: string = parts.length > 0 ? parts[parts.length - 1] : uri;
    try {
      return decodeURIComponent(last);
    } catch (err) {
      return last;
    }
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}
