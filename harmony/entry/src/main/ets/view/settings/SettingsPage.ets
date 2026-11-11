import { authState } from 'network';
import { ImmichSettings } from 'data';
import { i18n } from '@kit.LocalizationKit';
import { AppRuntime } from '../../runtime/AppRuntime';
import { AssetImageLoader } from '../timeline/AssetImageLoader';

/**
 * Settings tab: account info, language, cache management and sign-out.
 */
@ComponentV2
export struct SettingsPage {
  private static readonly LANG_ZH: string = 'zh-Hans';
  private static readonly LANG_EN: string = 'en-Latn-US';
  @Local busy: boolean = false;
  @Local cacheSizeText: string = '';
  @Local appLanguage: string = ImmichSettings.getAppLanguage();
  @Local langChooserVisible: boolean = false;

  aboutToAppear(): void {
    this.refreshCacheSize();
  }

  build() {
    Stack() {
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

        Column({ space: 0 }) {
          Text($r('app.string.settings_language'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 4 })
          Row() {
            Text($r('app.string.settings_language'))
              .fontSize(15)
              .fontColor($r('app.color.immich_text_secondary'))
            Blank()
            Text(this.languageDisplayName())
              .fontSize(15)
              .fontColor($r('app.color.immich_text_primary'))
            Image($r('app.media.ic_chevron_right'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.immich_text_secondary'))
              .padding({ left: 2 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
          .onClick(() => {
            this.langChooserVisible = true;
          })
        }
        .width('100%')
        .backgroundColor($r('app.color.immich_surface'))
        .borderRadius(14)
        .margin({ left: 12, right: 12, top: 16 })

        Column({ space: 0 }) {
          Text($r('app.string.settings_cache_title'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
            .padding({ left: 16, top: 12, bottom: 4 })
          Row() {
            Text($r('app.string.settings_cache_size'))
              .fontSize(15)
              .fontColor($r('app.color.immich_text_secondary'))
            Blank()
            Text(this.cacheSizeText.length > 0 ? this.cacheSizeText : '-')
              .fontSize(15)
              .fontColor($r('app.color.immich_text_primary'))
            Text($r('app.string.settings_cache_clear'))
              .fontSize(14)
              .fontColor($r('app.color.immich_error'))
              .padding({ left: 16 })
              .onClick(() => {
                this.confirmClearCache();
              })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
        .width('100%')
        .backgroundColor($r('app.color.immich_surface'))
        .borderRadius(14)
        .margin({ left: 12, right: 12, top: 16 })

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

      if (this.langChooserVisible) {
        this.LanguageChooser()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LanguageChooser() {
    Column() {
      Column({ space: 4 }) {
        Text($r('app.string.settings_language'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.immich_text_primary'))
          .padding({ top: 4, bottom: 8 })
        this.LanguageOption(SettingsPage.LANG_ZH, '中文')
        this.LanguageOption(SettingsPage.LANG_EN, 'English')
        Divider()
          .color($r('app.color.immich_outline'))
          .margin({ top: 4 })
        Text($r('app.string.common_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.immich_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            this.langChooserVisible = false;
          })
      }
      .alignItems(HorizontalAlign.Center)
      .width('76%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.immich_surface'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(0, 0, 0, 0.45)')
    .onClick(() => {
      this.langChooserVisible = false;
    })
  }

  @Builder
  LanguageOption(language: string, label: string) {
    Text(label)
      .fontSize(16)
      .fontColor(language === this.appLanguage
        ? $r('app.color.immich_primary') : $r('app.color.immich_text_primary'))
      .width('100%')
      .textAlign(TextAlign.Center)
      .padding({ top: 12, bottom: 12 })
      .onClick(() => {
        this.chooseLanguage(language);
      })
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

  private refreshCacheSize(): void {
    this.cacheSizeText = SettingsPage.formatBytes(AssetImageLoader.totalCacheBytes());
  }

  private static formatBytes(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    const kb: number = bytes / 1024;
    if (kb < 1024) {
      return `${kb.toFixed(1)} KB`;
    }
    const mb: number = kb / 1024;
    if (mb < 1024) {
      return `${mb.toFixed(1)} MB`;
    }
    const gb: number = mb / 1024;
    return `${gb.toFixed(2)} GB`;
  }

  private languageDisplayName(): string {
    return this.appLanguage === SettingsPage.LANG_ZH ? '中文' : 'English';
  }

  /** Apply the chosen language app-wide and persist it. */
  private chooseLanguage(language: string): void {
    this.langChooserVisible = false;
    if (language === this.appLanguage) {
      return;
    }
    try {
      i18n.System.setAppPreferredLanguage(language);
    } catch (err) {
      return;
    }
    ImmichSettings.setAppLanguage(language);
    this.appLanguage = language;
  }

  private confirmClearCache(): void {
    this.getUIContext().showAlertDialog({
      message: $r('app.string.settings_cache_clear_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.settings_cache_clear'),
        fontColor: $r('app.color.immich_error'),
        action: (): void => {
          AssetImageLoader.clearAllCaches();
          this.refreshCacheSize();
        }
      }
    });
  }
}
