import { ImmichAsset } from 'network';
import { AssetImageLoader } from './AssetImageLoader';

/**
 * One grid cell: thumbhash blur placeholder + asynchronously loaded
 * server thumbnail.
 */
@ComponentV2
export struct AssetThumbnail {
  @Param asset: ImmichAsset = new ImmichAsset();
  @Local loaded: PixelMap | null = null;
  @Local placeholder: PixelMap | null = null;

  aboutToAppear(): void {
    const asset: ImmichAsset = this.asset;
    AssetImageLoader.thumbhashPixelMap(asset).then((pm: PixelMap | null): void => {
      this.placeholder = pm;
    });
    AssetImageLoader.loadThumbnail(asset).then((pm: PixelMap): void => {
      this.loaded = pm;
    }).catch((err: Error): void => {
      // leave the placeholder in place on failure
    });
  }

  build() {
    Stack() {
      if (this.placeholder !== null && this.loaded === null) {
        Image(this.placeholder)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
      if (this.loaded !== null) {
        Image(this.loaded)
          .objectFit(ImageFit.Cover)
          .width('100%')
          .height('100%')
      }
      if (!this.asset.isImage) {
        Text(this.asset.durationMs > 0 ? this.formatDuration() : '')
          .fontSize(11)
          .fontColor(Color.White)
          .padding(4)
          .backgroundColor($r('app.color.immich_scrim'))
          .borderRadius(4)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_outline'))
  }

  private formatDuration(): string {
    const totalSeconds: number = Math.floor(this.asset.durationMs / 1000);
    const minutes: number = Math.floor(totalSeconds / 60);
    const seconds: number = totalSeconds % 60;
    return seconds < 10 ? `${minutes}:0${seconds}` : `${minutes}:${seconds}`;
  }
}
