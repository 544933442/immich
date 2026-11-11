import { ImmichAsset, ImmichApiError, ImmichAssetApi, ImmichAlbum, ImmichAlbumApi, ImmichBucket, ImmichMemory, ImmichMemoryApi } from 'network';
import { ImmichDateUtils } from 'commons';
import { i18n } from '@kit.LocalizationKit';
import { TimelineDataSource, TimelineRow } from './TimelineDataSource';
import { AssetThumbnail } from './AssetThumbnail';
import { AssetSelection } from './AssetSelection';
import { AssetImageLoader } from './AssetImageLoader';

/**
 * Server photo timeline: monthly buckets loaded progressively while the
 * user scrolls towards the end of the list. Long-pressing a cell enters
 * a multi-select mode with batch favorite / album / archive / trash.
 */
@ComponentV2
export struct TimelinePage {
  @Param pathStack: NavPathStack = new NavPathStack();
  @Local loading: boolean = true;
  @Local loadingMore: boolean = false;
  @Local errorText: string = '';
  @Local isEmpty: boolean = false;
  @Local isChinese: boolean = false;
  @Local selectionMode: boolean = false;
  @Local albumChooserVisible: boolean = false;
  @Local albumsLoading: boolean = false;
  @Local actionBusy: boolean = false;
  private dataSource: TimelineDataSource = new TimelineDataSource();
  private buckets: ImmichBucket[] = [];
  private nextBucket: number = 0;
  private selection: AssetSelection = new AssetSelection();
  private albums: ImmichAlbum[] = [];

  aboutToAppear(): void {
    this.isChinese = i18n.System.getAppPreferredLanguage().startsWith('zh');
    this.reload();
  }

  build() {
    Stack() {
      Column() {
        if (this.selectionMode) {
          this.SelectionBar()
        }
        if (this.errorText.length > 0 && this.dataSource.totalCount() === 0) {
          this.ErrorView()
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
        } else {
          List({ space: 0 }) {
            LazyForEach(this.dataSource, (row: TimelineRow) => {
              ListItem() {
                this.RowItem(row)
              }
            }, (row: TimelineRow) => `${row.bucket}_${row.startIndex}_${row.isHeader}_${this.selectionMode}`)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(6)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => {
            this.loadNextBucket();
          })
        }
        if (this.selectionMode) {
          this.ActionBar()
        }
      }
      .width('100%')
      .height('100%')

      if (this.albumChooserVisible) {
        this.AlbumChooser()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  @Builder
  SelectionBar() {
    Row({ space: 12 }) {
      Text(`${this.loadString('selection_selected')} ${this.selection.count()}`)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.immich_text_primary'))
        .layoutWeight(1)
      Button($r('app.string.common_cancel'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .controlSize(ControlSize.NORMAL)
        .enabled(!this.actionBusy)
        .onClick(() => {
          this.exitSelection();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.immich_surface'))
  }

  @Builder
  ActionBar() {
    Column() {
      Divider()
        .color($r('app.color.immich_outline'))
      Row() {
        Text($r('app.string.action_favorite'))
          .fontSize(14)
          .fontColor($r('app.color.immich_text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.batchFavorite();
          })
        Text($r('app.string.action_to_album'))
          .fontSize(14)
          .fontColor($r('app.color.immich_text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.openAlbumChooser();
          })
        Text($r('app.string.action_archive'))
          .fontSize(14)
          .fontColor($r('app.color.immich_text_primary'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.batchArchive();
          })
        Text($r('app.string.action_trash'))
          .fontSize(14)
          .fontColor($r('app.color.immich_error'))
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .onClick(() => {
            this.confirmBatchTrash();
          })
      }
      .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.immich_surface'))
  }

  @Builder
  AlbumChooser() {
    Column() {
      Column({ space: 12 }) {
        Text($r('app.string.album_chooser_title'))
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.immich_text_primary'))
        if (this.albumsLoading) {
          LoadingProgress()
            .width(30)
            .height(30)
            .color($r('app.color.immich_primary'))
            .margin({ top: 12, bottom: 12 })
        } else {
          Scroll() {
            Column() {
              ForEach(this.albums, (album: ImmichAlbum) => {
                Text(album.albumName)
                  .fontSize(15)
                  .fontColor($r('app.color.immich_text_primary'))
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .padding({ top: 12, bottom: 12 })
                  .onClick(() => {
                    this.confirmAlbumPick(album);
                  })
              }, (album: ImmichAlbum) => album.id)
              if (this.albums.length === 0) {
                Text($r('app.string.albums_empty'))
                  .fontSize(14)
                  .fontColor($r('app.color.immich_text_secondary'))
                  .padding(12)
              }
            }
            .width('100%')
          }
          .align(Alignment.Center)
          .constraintSize({ maxHeight: 300 })
          .scrollBar(BarState.Off)
        }
        Divider()
          .color($r('app.color.immich_outline'))
        Text($r('app.string.common_cancel'))
          .fontSize(15)
          .fontColor($r('app.color.immich_text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 10, bottom: 10 })
          .onClick(() => {
            this.albumChooserVisible = false;
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
      this.albumChooserVisible = false;
    })
  }

  @Builder
  RowItem(row: TimelineRow) {
    if (row.isMemories) {
      this.MemoriesLane(row)
    } else if (row.isHeader) {
      Text(row.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.immich_text_secondary'))
        .padding({ left: 12, top: 16, bottom: 6 })
        .width('100%')
    } else {
      Row({ space: 2 }) {
        ForEach(row.cells, (cell: ImmichAsset | null, index: number) => {
          if (cell !== null) {
            Column() {
              AssetThumbnail({ asset: cell })
            }
            .aspectRatio(1)
            .layoutWeight(1)
            .onClick(() => {
              this.openViewer(row.bucket, row.startIndex + index);
            })
          } else {
            Column()
              .aspectRatio(1)
              .layoutWeight(1)
              .backgroundColor($r('app.color.immich_bg'))
          }
        }, (cell: ImmichAsset | null, index: number) => `${row.startIndex}_${index}`)
      }
      .width('100%')
    }
  }

  @Builder
  MemoriesLane(row: TimelineRow) {
    Column({ space: 6 }) {
      Text($r('app.string.memories_title'))
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.immich_text_secondary'))
        .padding({ left: 12, top: 10 })
        .width('100%')
      Scroll() {
        Row({ space: 8 }) {
          ForEach(row.memories, (memory: ImmichMemory) => {
            MemoryCard({ memory: memory, isChinese: this.isChinese })
              .onClick(() => {
                this.openMemoryViewer(memory);
              })
          }, (memory: ImmichMemory) => memory.id)
        }
        .padding({ left: 12, right: 12 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .width('100%')
    }
    .width('100%')
    .padding({ bottom: 6 })
  }

  @Builder
  ErrorView() {
    Column({ space: 12 }) {
      Text(this.errorText)
        .fontSize(14)
        .fontColor($r('app.color.immich_error'))
        .textAlign(TextAlign.Center)
        .padding({ left: 24, right: 24 })
      Button($r('app.string.common_retry'))
        .buttonStyle(ButtonStyleMode.NORMAL)
        .onClick(() => {
          this.reload();
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.buckets = [];
    this.nextBucket = 0;
    this.dataSource.clear();
    try {
      this.buckets = await ImmichAssetApi.getTimeBuckets();
      let memories: ImmichMemory[] = [];
      try {
        memories = await ImmichMemoryApi.getMemories();
      } catch (err) {
        memories = [];
      }
      if (memories.length > 0) {
        this.dataSource.pushRows(TimelineDataSource.buildMemoriesRow(memories));
      }
      await this.loadNextBucket();
      this.isEmpty = this.dataSource.totalCount() <= 1 && this.buckets.length === 0;
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.loading = false;
  }

  private async loadNextBucket(): Promise<void> {
    if (this.loadingMore || this.loading || this.nextBucket >= this.buckets.length) {
      return;
    }
    this.loadingMore = true;
    try {
      const bucket: ImmichBucket = this.buckets[this.nextBucket];
      this.nextBucket += 1;
      const assets: ImmichAsset[] = await ImmichAssetApi.getTimeBucketAssets(bucket.timeBucket);
      const title: string = ImmichDateUtils.formatBucketTitle(bucket.timeBucket, this.isChinese);
      this.dataSource.pushRows(TimelineDataSource.buildRows(bucket.timeBucket, title, assets));
    } catch (err) {
      const message: string = err instanceof Error ? err.message : 'network error';
      if (this.dataSource.totalCount() === 0) {
        this.errorText = message;
      }
    } finally {
      this.loadingMore = false;
    }
  }

  private openViewer(bucket: string, index: number): void {
    const param: string = JSON.stringify({ bucket: bucket, index: index });
    this.pathStack.pushPathByName('viewer', param, false);
  }

  private openMemoryViewer(memory: ImmichMemory): void {
    const param: string = JSON.stringify({ memoryId: memory.id, index: 0 });
    this.pathStack.pushPathByName('viewer', param, false);
  }
}

/**
 * One memories lane card: cover photo with a years-ago label overlay.
 */
@ComponentV2
struct MemoryCard {
  @Param memory: ImmichMemory = new ImmichMemory();
  @Param isChinese: boolean = false;
  @Local cover: PixelMap | null = null;

  aboutToAppear(): void {
    if (this.memory.assets.length > 0) {
      const asset: ImmichAsset = this.memory.assets[0];
      AssetImageLoader.loadThumbnail(asset).then((pm: PixelMap): void => {
        this.cover = pm;
      }).catch((err: Error): void => {
        // gradient background stays
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.cover !== null) {
        Image(this.cover)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
      Column() {
        Text(this.yearsAgoLabel())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
          .maxLines(1)
      }
      .width('100%')
      .padding({ left: 8, right: 8, bottom: 8 })
      .linearGradient({
        angle: 180,
        colors: [['transparent', 0.4], [$r('app.color.immich_scrim'), 1.0]]
      })
    }
    .width(116)
    .height(150)
    .borderRadius(12)
    .clip(true)
    .backgroundColor($r('app.color.immich_outline'))
  }

  private yearsAgoLabel(): string {
    const currentYear: number = new Date().getFullYear();
    const yearsAgo: number = this.memory.year > 0 ? currentYear - this.memory.year : 0;
    if (yearsAgo > 0) {
      return this.isChinese ? `${yearsAgo} 年前` : `${yearsAgo} years ago`;
    }
    if (this.memory.title.length > 0) {
      return this.memory.title;
    }
    return this.isChinese ? '回忆' : 'Memory';
  }
}
