import { TimelineQuery } from 'network';
import { AssetBucketGridPage, NavStackHolder } from './AssetBucketGridPage';

/**
 * "favorites" route: all favorite assets via the timeline API with
 * isFavorite=true.
 */
@ComponentV2
export struct FavoritesPage {
  private query: TimelineQuery = TimelineQuery.favorites();
  private stackHolder: NavStackHolder = new NavStackHolder();
  private emptyText: string = '';

  aboutToAppear(): void {
    this.emptyText = this.loadString('favorites_empty');
  }

  build() {
    NavDestination() {
      AssetBucketGridPage({
        query: this.query,
        emptyText: this.emptyText,
        stackHolder: this.stackHolder
      })
    }
    .title($r('app.string.library_favorites'))
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

/** Route-table builder for the "favorites" destination. */
@Builder
export function FavoritesBuilder() {
  FavoritesPage()
}
