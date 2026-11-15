import { TimelineQuery } from 'network';
import { AssetBucketGridPage, NavStackHolder } from './AssetBucketGridPage';

/**
 * "trash" route: all trashed assets via the timeline API with isTrashed=true.
 */
@ComponentV2
export struct TrashPage {
  private query: TimelineQuery = TimelineQuery.trash();
  private stackHolder: NavStackHolder = new NavStackHolder();
  private emptyText: string = '';

  aboutToAppear(): void {
    this.emptyText = this.loadString('trash_empty');
  }

  build() {
    NavDestination() {
      AssetBucketGridPage({
        query: this.query,
        emptyText: this.emptyText,
        stackHolder: this.stackHolder
      })
    }
    .title($r('app.string.library_trash'))
    .backgroundColor($r('app.color.immich_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.stackHolder.stack = ctx.pathStack;
    })
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}

/** Route-table builder for the "trash" destination. */
@Builder
export function TrashBuilder() {
  TrashPage()
}
