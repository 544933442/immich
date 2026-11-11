import {
  ImmichAsset,
  ImmichAlbumApi,
  ImmichApiError,
  ImmichAssetApi,
  ImmichBucket,
  TimelineQuery
} from 'network';
import { TimelineDataSource, TimelineRow } from '../timeline/TimelineDataSource';
import { AssetSelection } from '../timeline/AssetSelection';
import { AssetThumbnail } from '../timeline/AssetThumbnail';

/** Raw shape of the assetPicker route parameter (JSON string). */
interface AssetPickerParamRaw {
  albumId: string;
}

/**
 * "assetPicker" route: multi-select grid of all photos; the confirmed
 * selection is added to the target album via PUT /albums/{id}/assets.
 */
@ComponentV2
export struct AssetPickerPage {
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local isEmpty: boolean = false;
  @Local busy: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private albumId: string = '';
  private query: TimelineQuery = TimelineQuery.allPhotos();
  private selection: AssetSelection = new AssetSelection();
  private dataSource: TimelineDataSource = new TimelineDataSource();
  private buckets: ImmichBucket[] = [];
  private nextBucket: number = 0;
  private loadingMore: boolean = false;
  private emptyText: string = '';

  build() {
    NavDestination() {
      Column() {
        if (this.errorText.length > 0 && this.dataSource.totalCount() === 0) {
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
        } else if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.immich_primary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.isEmpty) {
          Column({ space: 12 }) {
            Text(this.emptyText)
              .fontSize(14)
              .fontColor($r('app.color.immich_text_secondary'))
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 40, right: 40 })
        } else {
          List({ space: 0 }) {
            LazyForEach(this.dataSource, (row: TimelineRow) => {
              ListItem() {
                Row({ space: 2 }) {
                  ForEach(row.cells, (cell: ImmichAsset | null, index: number) => {
                    if (cell !== null) {
                      PickerCell({ asset: cell, selection: this.selection })
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
            }, (row: TimelineRow) => `${row.bucket}_${row.startIndex}`)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(6)
          .edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => {
            this.loadNextBucket();
          })
        }

        Row({ space: 12 }) {
          Text(`${this.selection.count()}`)
            .fontSize(15)
            .fontColor($r('app.color.immich_text_primary'))
            .layoutWeight(1)
          Button($r('app.string.picker_done'))
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .controlSize(ControlSize.NORMAL)
            .enabled(!this.busy && this.selection.count() > 0)
            .onClick(() => {
              this.submit();
            })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 10, bottom: 12 })
        .backgroundColor($r('app.color.immich_surface'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.immich_bg'))
    }
    .title($r('app.string.picker_title'))
    .backgroundColor($r('app.color.immich_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const param: string = typeof ctx.pathInfo.param === 'string' ? ctx.pathInfo.param : '';
      if (param.length > 0) {
        const raw: AssetPickerParamRaw = JSON.parse(param) as AssetPickerParamRaw;
        this.albumId = raw.albumId;
      }
      this.emptyText = this.loadString('picker_empty');
      this.reload();
    })
  }

  private async reload(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    this.buckets = [];
    this.nextBucket = 0;
    this.dataSource.clear();
    try {
      this.buckets = await ImmichAssetApi.getTimeBuckets(this.query);
      this.isEmpty = this.buckets.length === 0;
      await this.loadNextBucket();
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
      this.isEmpty = false;
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
      const assets: ImmichAsset[] = await ImmichAssetApi.getTimeBucketAssets(bucket.timeBucket, this.query);
      this.dataSource.pushRows(AssetPickerPage.buildCellRows(bucket.timeBucket, assets));
    } catch (err) {
      const message: string = err instanceof Error ? err.message : 'network error';
      if (this.dataSource.totalCount() === 0) {
        this.errorText = message;
      }
    } finally {
      this.loadingMore = false;
    }
  }

  private async submit(): Promise<void> {
    if (this.busy || this.albumId.length === 0 || this.selection.count() === 0) {
      return;
    }
    this.busy = true;
    try {
      const ids: string[] = this.selection.ids.slice();
      await ImmichAlbumApi.addAssetsToAlbum(this.albumId, ids);
      this.pathStack.pop();
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
      this.busy = false;
    }
  }

  /** Build 3-per-row chunks without month headers. */
  private static buildCellRows(bucket: string, assets: ImmichAsset[]): TimelineRow[] {
    const rows: TimelineRow[] = [];
    for (let i = 0; i < assets.length; i += 3) {
      const row: TimelineRow = new TimelineRow();
      row.isHeader = false;
      row.bucket = bucket;
      row.startIndex = i;
      for (let k = 0; k < 3; k++) {
        row.cells.push(i + k < assets.length ? assets[i + k] : null);
      }
      rows.push(row);
    }
    return rows;
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}

/** One selectable thumbnail cell. */
@ComponentV2
struct PickerCell {
  @Param asset: ImmichAsset = new ImmichAsset();
  @Param selection: AssetSelection = new AssetSelection();

  build() {
    Stack() {
      AssetThumbnail({ asset: this.asset })
      if (this.selection.isSelected(this.asset.id)) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.35)')
        Column() {
          Image($r('app.media.ic_check'))
            .width(16)
            .height(16)
            .fillColor(Color.White)
        }
        .width(24)
        .height(24)
        .borderRadius(12)
        .backgroundColor($r('app.color.immich_primary'))
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .aspectRatio(1)
    .onClick(() => {
      this.selection.toggle(this.asset.id);
    })
  }
}

/** Route-table builder for the "assetPicker" destination. */
@Builder
export function AssetPickerBuilder() {
  AssetPickerPage()
}
