import { NavStackHolder } from './AssetBucketGridPage';
import { AssetGridParam } from './AssetGridPage';
import { TimelineQueryRaw } from 'network';

/**
 * Library tab: entry cards for albums, people, favorites, archive and trash.
 */
@ComponentV2
export struct LibraryPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  private stackHolder: NavStackHolder = new NavStackHolder();

  aboutToAppear(): void {
    this.stackHolder.stack = this.pathStack;
  }

  build() {
    Column() {
      Text($r('app.string.library_title'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.immich_text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Column({ space: 10 }) {
        this.EntryCard($r('app.string.library_albums'), $r('app.string.library_albums_desc'),
          $r('app.media.ic_photo_album'), () => {
            this.stackHolder.stack.pushPathByName('albums', '', false);
          })
        this.EntryCard($r('app.string.people_title'), $r('app.string.people_desc'),
          $r('app.media.ic_group'), () => {
            this.stackHolder.stack.pushPathByName('people', '', false);
          })
        this.EntryCard($r('app.string.library_favorites'), $r('app.string.library_favorites_desc'),
          $r('app.media.ic_favorite'), () => {
            this.stackHolder.stack.pushPathByName('favorites', '', false);
          })
        this.EntryCard($r('app.string.library_archive'), $r('app.string.library_archive_desc'),
          $r('app.media.ic_archive'), () => {
            this.openArchive();
          })
        this.EntryCard($r('app.string.library_places'), $r('app.string.library_places_desc'),
          $r('app.media.ic_map'), () => {
            this.stackHolder.stack.pushPathByName('places', '', false);
          })
        this.EntryCard($r('app.string.library_trash'), $r('app.string.library_trash_desc'),
          $r('app.media.ic_delete'), () => {
            this.stackHolder.stack.pushPathByName('trash', '', false);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  @Builder
  EntryCard(title: Resource, desc: Resource, icon: Resource, onTap: () => void) {
    Row({ space: 12 }) {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor($r('app.color.immich_text_primary'))
      Column({ space: 3 }) {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.immich_text_primary'))
        Text(desc)
          .fontSize(12)
          .fontColor($r('app.color.immich_text_secondary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.immich_text_secondary'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.immich_surface'))
    .borderRadius(14)
    .onClick(() => {
      onTap();
    })
  }

  private openArchive(): void {
    const queryRaw: TimelineQueryRaw = { visibility: 'archive' };
    const param: AssetGridParam = { title: this.loadString('library_archive'), query: queryRaw };
    this.stackHolder.stack.pushPathByName('assetGrid', JSON.stringify(param), false);
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}
