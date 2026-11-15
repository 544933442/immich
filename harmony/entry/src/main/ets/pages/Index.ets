import { authState } from 'network';
import { AppRuntime } from '../runtime/AppRuntime';
import { LoginPage } from '../view/login/LoginPage';
import { MainShell } from '../view/shell/MainShell';

/**
 * App entry: bootstraps the runtime, then swaps between the login form and
 * the main tab shell. Pushed destinations come from the system route table.
 */
@Entry
@ComponentV2
struct Index {
  @Local ready: boolean = false;
  @Local initError: string = '';
  private pathStack: NavPathStack = new NavPathStack();

  aboutToAppear(): void {
    AppRuntime.whenReady()
      .then((): void => {
        this.ready = true;
      })
      .catch((err: Error): void => {
        this.initError = err.message;
        this.ready = true;
      });
  }

  build() {
    if (!this.ready) {
      Column({ space: 12 }) {
        Text('Immich')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.immich_primary'))
        LoadingProgress()
          .width(32)
          .height(32)
          .color($r('app.color.immich_primary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.immich_bg'))
    } else {
      Navigation(this.pathStack) {
        if (this.initError.length > 0) {
          Column({ space: 12 }) {
            Text(this.initError)
              .fontSize(14)
              .fontColor($r('app.color.immich_error'))
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.immich_bg'))
        } else if (authState.loggedIn) {
          MainShell({ pathStack: this.pathStack })
        } else {
          LoginPage()
        }
      }
      .mode(NavigationMode.Stack)
      .hideTitleBar(true)
      .width('100%')
      .height('100%')
    }
  }
}
