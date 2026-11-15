import { TimelineQuery, TimelineQueryRaw } from 'network';
import { AssetBucketGridPage, NavStackHolder } from './AssetBucketGridPage';

/** Raw shape of the assetGrid route parameter (JSON string). */
export interface AssetGridParam {
  title: string;
  query: TimelineQueryRaw;
}

/**
 * "assetGrid" route: generic bucket grid for any timeline query
 * (album, person, ...). The grid is created only after the route
 * parameter is available so its initial query is correct. Album
 * queries additionally offer an "add photos" entry.
 */
@ComponentV2
export struct AssetGridPage {
  @Local ready: boolean = false;
  @Local title: string = '';
  @Local reloadToken: number = 0;
  @Local albumId: string = '';
  private query: TimelineQuery = new TimelineQuery();
  private stackHolder: NavStackHolder = new NavStackHolder();
  private emptyText: string = '';

  build() {
    NavDestination() {
      if (this.ready) {
        Column() {
          AssetBucketGridPage({
            query: this.query,
            emptyText: this.emptyText,
            stackHolder: this.stackHolder,
            reloadToken: this.reloadToken
          })
            .layoutWeight(1)

          if (this.albumId.length > 0) {
            Button($r('app.string.album_add_photos'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .controlSize(ControlSize.NORMAL)
              .margin({ top: 8, bottom: 12 })
              .onClick(() => {
                this.openPicker();
              })
          }
        }
        .width('100%')
        .height('100%')
      } else {
        Column({ space: 12 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color($r('app.color.immich_primary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .title(this.title)
    .backgroundColor($r('app.color.immich_bg'))
    .onShown(() => {
      this.reloadToken += 1;
    })
    .onReady((ctx: NavDestinationContext) => {
      this.stackHolder.stack = ctx.pathStack;
      const param: string = typeof ctx.pathInfo.param === 'string' ? ctx.pathInfo.param : '';
      if (param.length > 0) {
        const raw: AssetGridParam = JSON.parse(param) as AssetGridParam;
        this.title = raw.title;
        this.query = TimelineQuery.fromRaw(raw.query);
        this.albumId = raw.query.albumId ?? '';
      }
      this.emptyText = this.loadString('grid_empty');
      this.ready = true;
    })
  }

  private openPicker(): void {
    this.stackHolder.stack.pushPathByName('assetPicker',
      JSON.stringify({ albumId: this.albumId }), false);
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}

/** Route-table builder for the "assetGrid" destination. */
@Builder
export function AssetGridBuilder() {
  AssetGridPage()
}
