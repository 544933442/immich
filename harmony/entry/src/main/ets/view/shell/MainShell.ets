import { ImmichSettings } from 'data';
import { authState } from 'network';
import { AppRuntime } from '../../runtime/AppRuntime';
import { BackupScheduler, backupState } from 'backup';
import { TimelinePage } from '../timeline/TimelinePage';
import { SearchPage } from '../search/SearchPage';
import { BackupPage } from '../backup/BackupPage';
import { SettingsPage } from '../settings/SettingsPage';
import { LibraryPage } from '../library/LibraryPage';

/**
 * Main tab shell: Photos / Search / Backup / Library / Settings.
 */
@ComponentV2
export struct MainShell {
  @Param pathStack: NavPathStack = new NavPathStack();
  @Local currentTab: number = 0;

  aboutToAppear(): void {
    if (authState.loggedIn) {
      // keep the periodic delayed-work registration in sync with settings
      BackupScheduler.sync();
      if (ImmichSettings.getBackupEnabled() && !backupState.running) {
        AppRuntime.runBackup().catch((err: Error): void => {
          // auto backup failure surfaces in the Backup page state
        });
      }
    }
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() {
        TimelinePage({ pathStack: this.pathStack })
      }
      .tabBar(this.TabItem($r('app.string.tab_photos'), 0))

      TabContent() {
        SearchPage({ pathStack: this.pathStack })
      }
      .tabBar(this.TabItem($r('app.string.tab_search'), 1))

      TabContent() {
        BackupPage()
      }
      .tabBar(this.TabItem($r('app.string.tab_backup'), 2))

      TabContent() {
        LibraryPage({ pathStack: this.pathStack })
      }
      .tabBar(this.TabItem($r('app.string.tab_library'), 3))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabItem($r('app.string.tab_settings'), 4))
    }
    .scrollable(false)
    .barHeight(56)
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  @Builder
  TabItem(title: Resource, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontWeight(index === this.currentTab ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentTab ? $r('app.color.immich_primary') : $r('app.color.immich_text_secondary'))
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
