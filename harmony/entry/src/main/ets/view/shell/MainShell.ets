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
      .tabBar(this.TabItem($r('app.string.tab_photos'), 0,
        $r('app.media.ic_photo_library'), $r('app.media.ic_photo_library_active')))

      TabContent() {
        SearchPage({ pathStack: this.pathStack })
      }
      .tabBar(this.TabItem($r('app.string.tab_search'), 1,
        $r('app.media.ic_search'), $r('app.media.ic_search_active')))

      TabContent() {
        BackupPage()
      }
      .tabBar(this.TabItem($r('app.string.tab_backup'), 2,
        $r('app.media.ic_backup'), $r('app.media.ic_backup_active')))

      TabContent() {
        LibraryPage({ pathStack: this.pathStack })
      }
      .tabBar(this.TabItem($r('app.string.tab_library'), 3,
        $r('app.media.ic_space_dashboard'), $r('app.media.ic_space_dashboard_active')))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.TabItem($r('app.string.tab_settings'), 4,
        $r('app.media.ic_settings'), $r('app.media.ic_settings_active')))
    }
    .scrollable(false)
    .barHeight(60)
    .onChange((index: number) => {
      this.currentTab = index;
    })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  @Builder
  TabItem(title: Resource, index: number, icon: Resource, activeIcon: Resource) {
    Column({ space: 2 }) {
      Image(index === this.currentTab ? activeIcon : icon)
        .width(24)
        .height(24)
        .fillColor(index === this.currentTab
          ? $r('app.color.immich_primary') : $r('app.color.immich_text_secondary'))
      Text(title)
        .fontSize(12)
        .fontWeight(index === this.currentTab ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(index === this.currentTab ? $r('app.color.immich_primary') : $r('app.color.immich_text_secondary'))
        .maxLines(1)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
