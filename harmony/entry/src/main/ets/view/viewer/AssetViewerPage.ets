import {
  ImmichAsset,
  ImmichAlbumApi,
  ImmichAssetApi,
  ImmichApiError,
  ImmichMemoryApi,
  ImmichSearchApi,
  TimelineQuery,
  TimelineQueryRaw
} from 'network';
import { ImmichDateUtils } from 'commons';
import { i18n } from '@kit.LocalizationKit';
import { AssetImageLoader } from '../timeline/AssetImageLoader';

/** Raw shape of the viewer route parameter (JSON string). */
interface ViewerParamRaw {
  bucket?: string;
  index: number;
  query?: TimelineQueryRaw;
  /** Natural-language smart search source. */
  searchQuery?: string;
  /** Memory card source. */
  memoryId?: string;
  /** Single-asset source (map marker etc.). */
  assetId?: string;
}

/**
 * Full-screen asset viewer pushed via the "viewer" system route:
 * horizontal swiper, thumbhash placeholder, preview quality images,
 * video download-then-play, favorite toggle and trash.
 */
@ComponentV2
export struct AssetViewerPage {
  @Local loading: boolean = true;
  @Local errorText: string = '';
  @Local assets: ImmichAsset[] = [];
  @Local index: number = 0;
  @Local showControls: boolean = true;
  @Local currentFavorite: boolean = false;
  @Local busy: boolean = false;
  @Local isChinese: boolean = false;
  @Local videoPath: string = '';
  @Local videoLoading: boolean = false;
  @Local offlineReady: boolean = false;
  @Local downloading: boolean = false;
  private pathStack: NavPathStack = new NavPathStack();
  private swiperController: SwiperController = new SwiperController();
  private pendingBucket: string = '';
  private query: TimelineQuery = new TimelineQuery();
  private searchQuery: string = '';
  private memoryId: string = '';
  private assetIdParam: string = '';
  private searchPage: number = 1;
  private searchHasMore: boolean = false;
  private searchLoadingMore: boolean = false;
  private static readonly SEARCH_PAGE_SIZE: number = 100;

  build() {
    NavDestination() {
      Column() {
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
            Text($r('app.string.timeline_loading'))
              .fontSize(14)
              .fontColor(Color.White)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.errorText.length > 0) {
          Column({ space: 12 }) {
            Text(this.errorText)
              .fontSize(14)
              .fontColor(Color.White)
              .textAlign(TextAlign.Center)
              .padding({ left: 32, right: 32 })
            Button($r('app.string.common_retry'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .backgroundColor(Color.Transparent)
              .fontColor(Color.White)
              .onClick(() => {
                this.loadAssets();
              })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Swiper(this.swiperController) {
            ForEach(this.assets, (asset: ImmichAsset, position: number) => {
              Stack() {
                if (position === this.index && !asset.isImage) {
                  this.VideoStage(asset)
                } else {
                  this.ImageStage(asset, position)
                }
              }
              .width('100%')
              .height('100%')
              .backgroundColor(Color.Black)
            }, (asset: ImmichAsset) => asset.id)
          }
          .index(this.index)
          .loop(false)
          .indicator(false)
          .width('100%')
          .layoutWeight(1)
          .onChange((position: number) => {
            this.onPageChanged(position);
          })
          .onClick(() => {
            this.showControls = !this.showControls;
          })

          if (this.showControls) {
            this.BottomBar()
          }
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Black)
    }
    .hideTitleBar(true)
    .backgroundColor(Color.Black)
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
      const param: string = typeof ctx.pathInfo.param === 'string' ? ctx.pathInfo.param : '';
      if (param.length > 0) {
        const raw: ViewerParamRaw = JSON.parse(param) as ViewerParamRaw;
        this.index = raw.index;
        if (raw.bucket !== undefined && raw.bucket !== null) {
          this.pendingBucket = raw.bucket;
        }
        if (raw.searchQuery !== undefined && raw.searchQuery !== null) {
          this.searchQuery = raw.searchQuery;
        }
        if (raw.memoryId !== undefined && raw.memoryId !== null) {
          this.memoryId = raw.memoryId;
        }
        if (raw.assetId !== undefined && raw.assetId !== null) {
          this.assetIdParam = raw.assetId;
        }
        this.query = TimelineQuery.fromRaw(raw.query);
      }
      this.isChinese = i18n.System.getAppPreferredLanguage().startsWith('zh');
      this.loadAssets();
    })
    .onBackPressed((): boolean => {
      this.pathStack.pop();
      return true;
    })
  }

  @Builder
  ImageStage(asset: ImmichAsset, position: number) {
    ViewerImage({ asset: asset, active: position === this.index })
      .width('100%')
      .height('100%')
  }

  @Builder
  VideoStage(asset: ImmichAsset) {
    Column({ space: 12 }) {
      if (this.videoPath.length > 0) {
        Video({
          src: this.videoPath,
          controller: this.videoController
        })
          .autoPlay(true)
          .controls(true)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
          .onFinish(() => {
            this.videoController.reset();
          })
      } else {
        Text(this.videoLoading ? $r('app.string.viewer_loading_video') : $r('app.string.viewer_video_play'))
          .fontSize(14)
          .fontColor(Color.White)
        if (this.videoLoading) {
          LoadingProgress()
            .width(28)
            .height(28)
            .color(Color.White)
        } else {
          Button($r('app.string.viewer_video_play'))
            .buttonStyle(ButtonStyleMode.EMPHASIZED)
            .backgroundColor($r('app.color.immich_primary'))
            .fontColor(Color.White)
            .onClick(() => {
              this.playVideo(asset);
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  BottomBar() {
    Row({ space: 8 }) {
      Text(this.currentDateLabel())
        .fontSize(13)
        .fontColor(Color.White)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Image(this.currentFavorite ? $r('app.media.ic_favorite_active') : $r('app.media.ic_favorite'))
        .width(24)
        .height(24)
        .fillColor(this.currentFavorite ? $r('app.color.immich_primary') : Color.White)
        .padding(10)
        .onClick(() => {
          this.toggleFavorite();
        })
      if (this.downloading) {
        LoadingProgress()
          .width(22)
          .height(22)
          .color(Color.White)
          .padding(10)
      } else {
        Image($r('app.media.ic_download'))
          .width(22)
          .height(22)
          .fillColor(this.offlineReady ? '#4ADE80' : Color.White)
          .padding(10)
          .onClick(() => {
            this.downloadCurrentOriginal();
          })
      }
      if (this.albumIdOf().length > 0) {
        Row({ space: 4 }) {
          Image($r('app.media.ic_remove_circle'))
            .width(16)
            .height(16)
            .fillColor(Color.White)
          Text($r('app.string.viewer_remove'))
            .fontSize(13)
            .fontColor(Color.White)
        }
        .alignItems(VerticalAlign.Center)
        .padding({ left: 8, right: 8, top: 12, bottom: 12 })
        .onClick(() => {
          this.confirmRemoveFromAlbum();
        })
      }
      Image($r('app.media.ic_delete'))
        .width(22)
        .height(22)
        .fillColor(Color.White)
        .padding(10)
        .onClick(() => {
          this.confirmDelete();
        })
    }
    .width('100%')
    .padding({ left: 16, right: 8, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.immich_scrim'))
  }

  private videoController: VideoController = new VideoController();

  private currentDateLabel(): string {
    if (this.index < 0 || this.index >= this.assets.length) {
      return '';
    }
    const asset: ImmichAsset = this.assets[this.index];
    if (asset.fileCreatedAt.length === 0) {
      return this.loadString('viewer_date_unknown');
    }
    return ImmichDateUtils.formatFullDate(asset.fileCreatedAt, this.isChinese);
  }

  private async loadAssets(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      if (this.searchQuery.length > 0) {
        this.searchPage = 1;
        const assets: ImmichAsset[] = await ImmichSearchApi.searchSmart(this.searchQuery,
          this.searchPage, AssetViewerPage.SEARCH_PAGE_SIZE);
        this.searchHasMore = assets.length >= AssetViewerPage.SEARCH_PAGE_SIZE;
        this.applyAssets(assets);
      } else if (this.memoryId.length > 0) {
        const memories = await ImmichMemoryApi.getMemories();
        let found: ImmichAsset[] = [];
        for (const memory of memories) {
          if (memory.id === this.memoryId) {
            found = memory.assets;
          }
        }
        this.applyAssets(found);
      } else if (this.assetIdParam.length > 0) {
        const asset: ImmichAsset = await ImmichAssetApi.getAssetById(this.assetIdParam);
        this.applyAssets([asset]);
      } else {
        const assets: ImmichAsset[] = await ImmichAssetApi.getTimeBucketAssets(this.pendingBucket, this.query);
        this.applyAssets(assets);
      }
    } catch (err) {
      const message: string = err instanceof ImmichApiError ? err.message : 'network error';
      this.errorText = message;
    }
    this.loading = false;
  }

  private applyAssets(assets: ImmichAsset[]): void {
    if (assets.length === 0) {
      this.errorText = this.loadString('viewer_empty');
      return;
    }
    this.assets = assets;
    if (this.index < 0 || this.index >= assets.length) {
      this.index = 0;
    }
    this.currentFavorite = this.assets[this.index].isFavorite;
    this.refreshOfflineState();
  }

  private async loadMoreSearch(): Promise<void> {
    if (!this.searchHasMore || this.searchLoadingMore || this.searchQuery.length === 0) {
      return;
    }
    this.searchLoadingMore = true;
    try {
      this.searchPage += 1;
      const more: ImmichAsset[] = await ImmichSearchApi.searchSmart(this.searchQuery,
        this.searchPage, AssetViewerPage.SEARCH_PAGE_SIZE);
      this.searchHasMore = more.length >= AssetViewerPage.SEARCH_PAGE_SIZE;
      this.assets = this.assets.concat(more);
    } catch (err) {
      this.searchHasMore = false;
    } finally {
      this.searchLoadingMore = false;
    }
  }

  private onPageChanged(position: number): void {
    this.index = position;
    this.videoPath = '';
    this.videoLoading = false;
    this.videoController.reset();
    if (position >= 0 && position < this.assets.length) {
      this.currentFavorite = this.assets[position].isFavorite;
    }
    this.refreshOfflineState();
    if (this.searchQuery.length > 0 && position >= this.assets.length - 8) {
      this.loadMoreSearch();
    }
  }

  private async toggleFavorite(): Promise<void> {
    if (this.busy || this.index >= this.assets.length) {
      return;
    }
    const asset: ImmichAsset = this.assets[this.index];
    const target: boolean = !asset.isFavorite;
    this.busy = true;
    try {
      await ImmichAssetApi.setFavorite([asset.id], target);
      asset.isFavorite = target;
      this.currentFavorite = target;
    } catch (err) {
      // keep previous state on failure
    } finally {
      this.busy = false;
    }
  }

  private confirmDelete(): void {
    if (this.busy || this.index >= this.assets.length) {
      return;
    }
    this.getUIContext().showAlertDialog({
      message: $r('app.string.viewer_delete_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.viewer_delete_ok'),
        fontColor: $r('app.color.immich_error'),
        action: (): void => {
          this.deleteCurrent();
        }
      }
    });
  }

  private async deleteCurrent(): Promise<void> {
    if (this.index >= this.assets.length) {
      return;
    }
    const asset: ImmichAsset = this.assets[this.index];
    this.busy = true;
    try {
      await ImmichAssetApi.deleteAssets([asset.id], false);
      this.removeCurrentFromList();
    } catch (err) {
      // keep the asset visible on failure
    } finally {
      this.busy = false;
    }
  }

  /** Album id when the viewer was opened from an album query, else ''. */
  private albumIdOf(): string {
    return this.query.albumId ?? '';
  }

  private confirmRemoveFromAlbum(): void {
    if (this.busy || this.index >= this.assets.length) {
      return;
    }
    this.getUIContext().showAlertDialog({
      message: $r('app.string.viewer_remove_confirm'),
      primaryButton: {
        value: $r('app.string.common_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.viewer_remove'),
        fontColor: $r('app.color.immich_error'),
        action: (): void => {
          this.removeFromAlbum();
        }
      }
    });
  }

  private async removeFromAlbum(): Promise<void> {
    const albumId: string = this.albumIdOf();
    if (albumId.length === 0 || this.busy || this.index >= this.assets.length) {
      return;
    }
    const asset: ImmichAsset = this.assets[this.index];
    this.busy = true;
    try {
      await ImmichAlbumApi.removeAssetsFromAlbum(albumId, [asset.id]);
      this.removeCurrentFromList();
    } catch (err) {
      // keep the asset in the viewer on failure
    } finally {
      this.busy = false;
    }
  }

  /** Drop the current asset from the swiper and advance (or pop if empty). */
  private removeCurrentFromList(): void {
    const remaining: ImmichAsset[] = this.assets.slice(0, this.index)
      .concat(this.assets.slice(this.index + 1));
    if (remaining.length === 0) {
      this.pathStack.pop();
      return;
    }
    this.assets = remaining;
    if (this.index >= remaining.length) {
      this.index = remaining.length - 1;
    }
    this.currentFavorite = this.assets[this.index].isFavorite;
    this.videoPath = '';
    this.videoController.reset();
  }

  private async playVideo(asset: ImmichAsset): Promise<void> {
    this.videoLoading = true;
    try {
      const path: string = await AssetImageLoader.loadVideoFile(asset);
      this.videoPath = `file://${path}`;
    } catch (err) {
      this.errorText = '';
    } finally {
      this.videoLoading = false;
    }
  }

  /** Recompute the offline indicator for the current asset. */
  private refreshOfflineState(): void {
    if (this.index < 0 || this.index >= this.assets.length) {
      this.offlineReady = false;
      return;
    }
    this.offlineReady = AssetImageLoader.isAvailableOffline(this.assets[this.index]);
  }

  /** Download the current asset original for offline use. */
  private async downloadCurrentOriginal(): Promise<void> {
    if (this.busy || this.downloading || this.index >= this.assets.length) {
      return;
    }
    this.downloading = true;
    try {
      await AssetImageLoader.downloadOriginal(this.assets[this.index]);
      this.offlineReady = true;
    } catch (err) {
      // indicator keeps previous state on failure
    } finally {
      this.downloading = false;
    }
  }

  private loadString(name: string): string {
    const context: Context | undefined = this.getUIContext().getHostContext();
    if (context === undefined) {
      return '';
    }
    return context.resourceManager.getStringByNameSync(name);
  }
}

/**
 * One swiper page for images: preview pixel map with thumbhash fallback.
 */
@ComponentV2
struct ViewerImage {
  @Param asset: ImmichAsset = new ImmichAsset();
  @Param active: boolean = false;
  @Local preview: PixelMap | null = null;
  @Local placeholder: PixelMap | null = null;

  aboutToAppear(): void {
    const asset: ImmichAsset = this.asset;
    AssetImageLoader.thumbhashPixelMap(asset).then((pm: PixelMap | null): void => {
      this.placeholder = pm;
    });
    if (this.active) {
      AssetImageLoader.loadPreview(asset).then((pm: PixelMap): void => {
        this.preview = pm;
      }).catch((err: Error): void => {
        // placeholder / spinner stays
      });
    }
  }

  build() {
    Stack() {
      if (this.placeholder !== null && this.preview === null) {
        Image(this.placeholder)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
      if (this.preview !== null) {
        Image(this.preview)
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')
      }
      if (this.preview === null && this.placeholder === null) {
        LoadingProgress()
          .width(30)
          .height(30)
          .color(Color.White)
      }
    }
    .width('100%')
    .height('100%')
  }

  @Monitor('active')
  onActiveChange(): void {
    if (this.active && this.preview === null) {
      const asset: ImmichAsset = this.asset;
      AssetImageLoader.loadPreview(asset).then((pm: PixelMap): void => {
        this.preview = pm;
      }).catch((err: Error): void => {
        // placeholder / spinner stays
      });
    }
  }
}

/** Route-table builder for the "viewer" destination. */
@Builder
export function ViewerBuilder() {
  AssetViewerPage()
}
