import { ImmichAlbum, ImmichAlbumApi, ImmichApiError, TimelineQueryRaw } from 'network';
import { AssetImageLoader } from '../timeline/AssetImageLoader';
import { NavStackHolder } from './AssetBucketGridPage';
import { AssetGridParam } from './AssetGridPage';

/** One album cover: async thumbnail by asset id with placeholder. */
@ComponentV2
struct AlbumCover {
  @Param assetId: string = '';
  @Local loaded: PixelMap | null = null;

  aboutToAppear(): void {
    const assetId: string = this.assetId;
    AssetImageLoader.loadThumbnailById(assetId).then((pm: PixelMap): void => {
      this.loaded = pm;
    }).catch((err: Error): void => {
      // placeholder stays
    });
  }

  build() {
    Stack() {
      if (this.loaded !== null) {
        Image(this.loaded)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      } else {
        Column()
          .width('100%')
          .height('100%')
      }
    }
    .width(64)
    .height(64)
    .borderRadius(8)
    .backgroundColor($r('app.color.immich_outline'))
    .clip(true)
  }
}

/**
 * "albums" route: list of server albums with cover, count and date range.
 */
@ComponentV2
export struct AlbumsPage {
  @Local albums: ImmichAlbum[] = [];
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local creating: boolean = false;
  @Local creatingBusy: boolean = false;
  @Local newAlbumName: string = '';
  @Local createError: string = '';
  @Local menuAlbum: ImmichAlbum | null = null;
  @Local renameTarget: ImmichAlbum | null = null;
  @Local deleteTarget: ImmichAlbum | null = null;
  private stackHolder: NavStackHolder = new NavStackHolder();

  aboutToAppear(): void {
    this.loadAlbums();
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          if (this.errorText.length > 0) {
            Column({ space: 12 }) {
              Text(this.errorText)
                .fontSize(14)
                .fontColor($r('app.color.immich_error'))
                .textAlign(TextAlign.Center)
                .padding({ left: 24, right: 24 })
              Button($r('app.string.common_retry'))
                .buttonStyle(ButtonStyleMode.NORMAL)
                .onClick(() => {
                  this.loadAlbums();
                })
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.loading) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(36)
                .height(36)
                .color($r('app.color.immich_primary'))
              Text($r('app.string.timeline_loading'))
                .fontSize(14)
                .fontColor($r('app.color.immich_text_secondary'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else if (this.albums.length === 0) {
            Column({ space: 12 }) {
              Text($r('app.string.albums_empty'))
                .fontSize(14)
                .fontColor($r('app.color.immich_text_secondary'))
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding({ left: 40, right: 40 })
          } else {
            List({ space: 0 }) {
              ForEach(this.albums, (album: ImmichAlbum) => {
                ListItem() {
                  Row({ space: 14 }) {
                    AlbumCover({ assetId: album.albumThumbnailAssetId })
                    Column({ space: 4 }) {
                      Text(album.albumName)
                        .fontSize(16)
                        .fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.immich_text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                      Text(`${album.assetCount} ${this.itemsLabel()}`)
                        .fontSize(13)
                        .fontColor($r('app.color.immich_text_secondary'))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 10, bottom: 10 })
                  .onClick(() => {
                    this.openAlbum(album);
                  })
                  .gesture(LongPressGesture()
                    .onAction(() => {
                      this.menuAlbum = album;
                    }))
                }
              }, (album: ImmichAlbum) => album.id)
            }
            .width('100%')
            .layoutWeight(1)
            .divider({ strokeWidth: 1, color: $r('app.color.immich_outline'), startMargin: 94, endMargin: 0 })
            .edgeEffect(EdgeEffect.Spring)
          }
          Button($r('app.string.album_create'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .controlSize(ControlSize.NORMAL)
            .margin({ top: 8, bottom: 16 })
            .onClick(() => {
              this.openCreate();
            })
        }
        .width('100%')
        .height('100%')

        if (this.creating || this.renameTarget !== null) {
          Column() {
            Column({ space: 16 }) {
              Text(this.renameTarget !== null ? $r('app.string.album_rename') : $r('app.string.album_create'))
                .fontSize(18)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.immich_text_primary'))
              TextInput({ text: this.newAlbumName, placeholder: $r('app.string.album_name_hint') })
                .fontSize(15)
                .onChange((value: string) => {
                  this.newAlbumName = value;
                })
              if (this.createError.length > 0) {
                Text(this.createError)
                  .fontSize(13)
                  .fontColor($r('app.color.immich_error'))
              }
              Row({ space: 12 }) {
                Button($r('app.string.common_cancel'))
                  .buttonStyle(ButtonStyleMode.NORMAL)
                  .layoutWeight(1)
                  .enabled(!this.creatingBusy)
                  .onClick(() => {
                    this.closeDialog();
                  })
                Button($r('app.string.common_create'))
                  .buttonStyle(ButtonStyleMode.EMPHASIZED)
                  .layoutWeight(1)
                  .enabled(!this.creatingBusy && this.newAlbumName.trim().length > 0)
                  .onClick(() => {
                    this.submitDialog();
                  })
              }
              .width('100%')
            }
            .alignItems(HorizontalAlign.Start)
            .width('86%')
            .padding(20)
            .borderRadius(16)
            .backgroundColor($r('app.color.immich_surface'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor('rgba(0, 0, 0, 0.45)')
          .onClick(() => {
            if (!this.creatingBusy) {
              this.closeDialog();
            }
          })
        }

        if (this.menuAlbum !== null) {
          this.AlbumMenu(this.menuAlbum)
        }

        if (this.deleteTarget !== null) {
          this.DeleteConfirm(this.deleteTarget)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.library_albums'))
    .backgroundColor($r('app.color.immich_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.stackHolder.stack = ctx.pathStack;
    })
  }

  private async loadAlbums(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      this.albums = await ImmichAlbumApi.getAlbums();
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.loading = false;
  }

  private openAlbum(album: ImmichAlbum): void {
    const queryRaw: TimelineQueryRaw = { albumId: album.id };
    const param: AssetGridParam = { title: album.albumName, query: queryRaw };
    this.stackHolder.stack.pushPathByName('assetGrid', JSON.stringify(param), false);
  }

  @Builder
  EntryMenuBackdrop(onClose: () => void) {
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('rgba(0, 0, 0, 0.45)')
      .onClick(() => {
        onClose();
      })
  }

  @Builder
  AlbumMenu(album: ImmichAlbum) {
    Stack() {
      this.EntryMenuBackdrop(() => {
        this.menuAlbum = null;
      })
      Column({ space: 8 }) {
        Text(album.albumName)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.immich_text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .padding({ top: 8, bottom: 8 })
        Text($r('app.string.album_rename'))
          .fontSize(16)
          .fontColor($r('app.color.immich_text_primary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.openRename(album);
          })
        Text($r('app.string.album_delete'))
          .fontSize(16)
          .fontColor($r('app.color.immich_error'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.menuAlbum = null;
            this.deleteTarget = album;
          })
        Divider()
          .color($r('app.color.immich_outline'))
          .margin({ top: 4, bottom: 4 })
        Text($r('app.string.common_cancel'))
          .fontSize(16)
          .fontColor($r('app.color.immich_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.menuAlbum = null;
          })
      }
      .alignItems(HorizontalAlign.Center)
      .width('70%')
      .padding(16)
      .borderRadius(16)
      .backgroundColor($r('app.color.immich_surface'))
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  DeleteConfirm(album: ImmichAlbum) {
    Stack() {
      this.EntryMenuBackdrop(() => {
        this.deleteTarget = null;
      })
      Column({ space: 16 }) {
        Text($r('app.string.album_delete_confirm'))
          .fontSize(16)
          .fontColor($r('app.color.immich_text_primary'))
          .textAlign(TextAlign.Center)
        Row({ space: 12 }) {
          Button($r('app.string.common_cancel'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .layoutWeight(1)
            .onClick(() => {
              this.deleteTarget = null;
            })
          Button($r('app.string.album_delete'))
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .layoutWeight(1)
            .backgroundColor($r('app.color.immich_error'))
            .onClick(() => {
              this.submitDelete();
            })
        }
        .width('100%')
      }
      .alignItems(HorizontalAlign.Center)
      .width('80%')
      .padding(20)
      .borderRadius(16)
      .backgroundColor($r('app.color.immich_surface'))
    }
    .width('100%')
    .height('100%')
  }

  private openCreate(): void {
    this.renameTarget = null;
    this.menuAlbum = null;
    this.newAlbumName = '';
    this.createError = '';
    this.creating = true;
  }

  private openRename(album: ImmichAlbum): void {
    this.menuAlbum = null;
    this.renameTarget = album;
    this.newAlbumName = album.albumName;
    this.createError = '';
    this.creating = false;
  }

  private closeDialog(): void {
    this.creating = false;
    this.renameTarget = null;
  }

  private submitDialog(): void {
    if (this.renameTarget !== null) {
      this.submitRename(this.renameTarget);
    } else {
      this.submitCreate();
    }
  }

  private async submitCreate(): Promise<void> {
    const name: string = this.newAlbumName.trim();
    if (name.length === 0 || this.creatingBusy) {
      return;
    }
    this.creatingBusy = true;
    this.createError = '';
    try {
      await ImmichAlbumApi.createAlbum(name);
      this.closeDialog();
      this.newAlbumName = '';
      await this.loadAlbums();
    } catch (err) {
      this.createError = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.creatingBusy = false;
  }

  private async submitRename(album: ImmichAlbum): Promise<void> {
    const name: string = this.newAlbumName.trim();
    if (name.length === 0 || this.creatingBusy) {
      return;
    }
    this.creatingBusy = true;
    this.createError = '';
    try {
      await ImmichAlbumApi.updateAlbumName(album.id, name);
      this.closeDialog();
      this.newAlbumName = '';
      await this.loadAlbums();
    } catch (err) {
      this.createError = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.creatingBusy = false;
  }

  private async submitDelete(): Promise<void> {
    const album: ImmichAlbum | null = this.deleteTarget;
    if (album === null || this.creatingBusy) {
      return;
    }
    this.creatingBusy = true;
    try {
      await ImmichAlbumApi.deleteAlbum(album.id);
    } catch (err) {
      // album stays listed on failure
    }
    this.deleteTarget = null;
    await this.loadAlbums();
    this.creatingBusy = false;
  }

  private itemsLabel(): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync('library_items');
  }
}

/** Route-table builder for the "albums" destination. */
@Builder
export function AlbumsBuilder() {
  AlbumsPage()
}
