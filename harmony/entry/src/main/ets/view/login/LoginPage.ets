import { ImmichApiConfig, ImmichAuthApi, ImmichLoginResponseRaw, authState } from 'network';
import { CredentialStore, ImmichSettings } from 'data';

/** Server URL + email/password login form. */
@ComponentV2
export struct LoginPage {
  @Local serverUrl: string = '';
  @Local email: string = '';
  @Local password: string = '';
  @Local busy: boolean = false;
  @Local errorText: string = '';

  build() {
    Scroll() {
      Column({ space: 0 }) {
      Column({ space: 10 }) {
        Text($r('app.string.login_title'))
          .fontSize(34)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.immich_primary'))
        Text($r('app.string.login_subtitle'))
          .fontSize(14)
          .fontColor($r('app.color.immich_text_secondary'))
      }
      .width('100%')
      .margin({ top: 72, bottom: 40 })

      Column({ space: 14 }) {
        Column({ space: 6 }) {
          Text($r('app.string.login_server_url'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
          TextInput({ placeholder: 'https://photos.example.com', text: this.serverUrl })
            .onChange((value: string) => {
              this.serverUrl = value.trim();
            })
            .height(48)
            .backgroundColor($r('app.color.immich_surface'))
            .borderRadius(10)
            .enabled(!this.busy)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text($r('app.string.login_email'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
          TextInput({ placeholder: 'user@example.com', text: this.email })
            .onChange((value: string) => {
              this.email = value.trim();
            })
            .height(48)
            .backgroundColor($r('app.color.immich_surface'))
            .borderRadius(10)
            .enabled(!this.busy)
        }
        .width('100%')

        Column({ space: 6 }) {
          Text($r('app.string.login_password'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
            .width('100%')
          TextInput({ placeholder: '********', text: this.password })
            .type(InputType.Password)
            .onChange((value: string) => {
              this.password = value;
            })
            .height(48)
            .backgroundColor($r('app.color.immich_surface'))
            .borderRadius(10)
            .enabled(!this.busy)
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 24, right: 24 })

      if (this.errorText.length > 0) {
        Text(this.errorText)
          .fontSize(13)
          .fontColor($r('app.color.immich_error'))
          .padding({ left: 24, right: 24, top: 16 })
          .textAlign(TextAlign.Center)
      }

      Button(this.busy ? $r('app.string.login_loading') : $r('app.string.login_button'))
        .buttonStyle(ButtonStyleMode.EMPHASIZED)
        .backgroundColor($r('app.color.immich_primary'))
        .fontColor($r('app.color.immich_on_primary'))
        .width('60%')
        .height(46)
        .margin({ top: 32 })
        .enabled(!this.busy)
        .onClick(() => {
          this.login();
        })

      if (this.busy) {
        LoadingProgress()
          .width(28)
          .height(28)
          .color($r('app.color.immich_primary'))
          .margin({ top: 16 })
      }
      }
      .width('100%')
      .constraintSize({ minHeight: '100%' })
      .backgroundColor($r('app.color.immich_bg'))
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  private async login(): Promise<void> {
    this.getUIContext().getFocusController().clearFocus();
    if (this.serverUrl.length === 0 || this.email.length === 0 || this.password.length === 0) {
      this.errorText = this.loadString('login_fill_all');
      return;
    }
    this.busy = true;
    this.errorText = '';
    try {
      const response: ImmichLoginResponseRaw = await ImmichAuthApi.login(this.serverUrl, this.email, this.password);
      ImmichApiConfig.setServer(this.serverUrl);
      const normalized: string = ImmichApiConfig.getServer();
      ImmichApiConfig.setToken(response.accessToken);
      await CredentialStore.saveToken(response.accessToken);
      ImmichSettings.setServerUrl(normalized);
      ImmichSettings.setUserName(response.name);
      ImmichSettings.setUserEmail(response.userEmail);
      authState.serverUrl = normalized;
      authState.userName = response.name;
      authState.userEmail = response.userEmail;
      authState.loggedIn = true;
    } catch (err) {
      const message: string = err instanceof Error ? err.message : 'login failed';
      this.errorText = message;
    } finally {
      this.busy = false;
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
