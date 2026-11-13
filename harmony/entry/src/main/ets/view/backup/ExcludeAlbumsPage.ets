import { BusinessError } from '@kit.BasicServicesKit';
import { BackupScheduler, GalleryAlbumInfo, GalleryMediaScanner, backupState } from 'backup';
import { ImmichSettings } from 'data';
import { AppRuntime } from '../../runtime/AppRuntime';

/**
 * Gallery backup exclusion management: pick albums (user albums plus the
 * system video/image albums) whose content should not be backed up.
 */
@ComponentV2
export struct ExcludeAlbumsPage {
  @Local albums: GalleryAlbumInfo[] = [];
  @Local loading: boolean = true;
  @Local errorText: string = '';

  aboutToAppear(): void {
    backupState.excludedAlbumCount = ImmichSettings.getGalleryExcludedAlbums().length;
    this.loadAlbums();
  }

  build() {
    NavDestination() {
      if (this.loading) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.immich_primary'))
          Text($r('app.string.timeline_loading'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.errorText.length > 0) {
        Column({ space: 10 }) {
          Text(this.errorText)
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
          Button($r('app.string.common_retry'))
            .buttonStyle(ButtonStyleMode.NORMAL)
            .controlSize(ControlSize.SMALL)
            .onClick(() => {
              this.loadAlbums();
            })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.albums.length === 0) {
        Column() {
          Text($r('app.string.backup_albums_empty'))
            .fontSize(13)
            .fontColor($r('app.color.immich_text_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.albums, (album: GalleryAlbumInfo) => {
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(album.name)
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.immich_text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(String(album.count))
                    .fontSize(12)
                    .fontColor($r('app.color.immich_text_secondary'))
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Toggle({ type: ToggleType.Switch, isOn: this.isExcluded(album) })
                  .onChange((isOn: boolean) => {
                    this.setExcluded(album, isOn);
                  })
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.immich_surface'))
              .borderRadius(14)
            }, (album: GalleryAlbumInfo) => album.uri)
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 4, bottom: 16 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
      }
    }
    .title($r('app.string.backup_exclude_albums'))
    .backgroundColor($r('app.color.immich_bg'))
    .onDisAppear(() => {
      AppRuntime.getEngine().refreshPending().catch((err: Error): void => {
      });
      BackupScheduler.sync();
    })
  }

  private loadAlbums(): void {
    this.loading = true;
    this.errorText = '';
    GalleryMediaScanner.listGalleryAlbums(AppRuntime.getContext()).then((albums: GalleryAlbumInfo[]) => {
      this.albums = albums;
      this.loading = false;
    }).catch((err: BusinessError) => {
      this.errorText = err.message;
      this.loading = false;
    });
  }

  private isExcluded(album: GalleryAlbumInfo): boolean {
    return ImmichSettings.getGalleryExcludedAlbums().indexOf(album.uri) >= 0;
  }

  private setExcluded(album: GalleryAlbumInfo, excluded: boolean): void {
    const current: string[] = ImmichSettings.getGalleryExcludedAlbums();
    const next: string[] = [];
    for (const uri of current) {
      if (uri !== album.uri) {
        next.push(uri);
      }
    }
    if (excluded) {
      next.push(album.uri);
    }
    ImmichSettings.setGalleryExcludedAlbums(next);
    backupState.excludedAlbumCount = next.length;
  }
}

/** Route-table builder for the "excludeAlbums" destination. */
@Builder
export function ExcludeAlbumsBuilder() {
  ExcludeAlbumsPage()
}
