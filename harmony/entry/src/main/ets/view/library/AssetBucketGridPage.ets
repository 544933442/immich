import { ImmichAsset, ImmichApiError, ImmichAssetApi, ImmichBucket, TimelineQuery } from 'network';
import { ImmichDateUtils } from 'commons';
import { i18n } from '@kit.LocalizationKit';
import { TimelineDataSource, TimelineRow } from '../timeline/TimelineDataSource';
import { AssetThumbnail } from '../timeline/AssetThumbnail';

/** Mutable holder so embedded pages read the live NavPathStack at click time. */
export class NavStackHolder {
  stack: NavPathStack = new NavPathStack();
}

/**
 * Reusable bucket-based asset grid (3 columns, month headers, progressive
 * loading) driven by an arbitrary server-side TimelineQuery. Used by the
 * favorites, trash and album detail pages.
 */
@ComponentV2
export struct AssetBucketGridPage {
  @Param query: TimelineQuery = new TimelineQuery();
  @Param emptyText: string = '';
  @Param stackHolder: NavStackHolder = new NavStackHolder();
  /** Bumped by the host page when the destination is shown again. */
  @Param reloadToken: number = 0;
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local isEmpty: boolean = false;
  @Local isChinese: boolean = false;
  private dataSource: TimelineDataSource = new TimelineDataSource();
  private buckets: ImmichBucket[] = [];
  private nextBucket: number = 0;
  private loadingMore: boolean = false;
  private lastToken: number = 0;

  aboutToAppear(): void {
    this.isChinese = i18n.System.getAppPreferredLanguage().startsWith('zh');
    this.reload();
  }

  @Monitor('reloadToken')
  onReloadTokenChange(): void {
    if (this.lastToken === 0) {
      // first show already loaded in aboutToAppear
      this.lastToken = this.reloadToken;
      return;
    }
    this.lastToken = this.reloadToken;
    this.reload();
  }

  build() {
    Column() {
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
              this.RowItem(row)
            }
          }, (row: TimelineRow) => `${row.bucket}_${row.startIndex}_${row.isHeader}`)
        }
        .width('100%')
        .layoutWeight(1)
        .cachedCount(6)
        .edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => {
          this.loadNextBucket();
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  @Builder
  RowItem(row: TimelineRow) {
    if (row.isHeader) {
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
    const param: string = JSON.stringify({ bucket: bucket, index: index, query: this.query.toRaw() });
    this.stackHolder.stack.pushPathByName('viewer', param, false);
  }
}
