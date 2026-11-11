import { authState } from 'network';
import { AppRuntime } from '../../runtime/AppRuntime';

/**
 * Settings tab: account info, server URL and sign-out.
 */
@ComponentV2
export struct SettingsPage {
  @Local busy: boolean = false;

  build() {
    Column() {
      Text($r('app.string.tab_settings'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.immich_text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Column({ space: 0 }) {
        Text($r('app.string.settings_user_title'))
          .fontSize(13)
          .fontColor($r('app.color.immich_text_secondary'))
          .width('100%')
          .padding({ left: 16, top: 12, bottom: 4 })
        this.InfoRow($r('app.string.settings_name'), authState.userName)
        Divider().color($r('app.color.immich_outline')).margin({ left: 16 })
        this.InfoRow($r('app.string.settings_email'), authState.userEmail)
        Divider().color($r('app.color.immich_outline')).margin({ left: 16 })
        this.InfoRow($r('app.string.settings_server'), authState.serverUrl)
      }
      .width('100%')
      .backgroundColor($r('app.color.immich_surface'))
      .borderRadius(14)
      .margin({ left: 12, right: 12 })

      Button($r('app.string.settings_logout'))
        .buttonStyle(ButtonStyleMode.EMPHASIZED)
        .backgroundColor($r('app.color.immich_error'))
        .fontColor(Color.White)
        .width('100%')
        .height(46)
        .margin({ left: 12, right: 12, top: 24 })
        .enabled(!this.busy)
        .onClick(() => {
          this.confirmLogout();
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  InfoRow(label: Resource, value: string) {
    Row() {
      Text(label)
        .fontSize(15)
        .fontColor($r('app.color.immich_text_secondary'))
      Blank()
      Text(value.length > 0 ? value : '-')
        .fontSize(15)
        .fontColor($r('app.color.immich_text_primary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: '60%' })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 12 })
  }

  private confirmLogout(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.settings_logout_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_logout'),
        fontColor: $r('app.color.immich_error'),
        action: (): void => {
          this.doLogout();
        }
      }
    });
  }

  private async doLogout(): Promise<void> {
    this.busy = true;
    try {
      await AppRuntime.logout();
    } finally {
      this.busy = false;
    }
  }
}
