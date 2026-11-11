import { ImmichAsset, ImmichApiError, ImmichSearchApi } from 'network';
import { AssetThumbnail } from '../timeline/AssetThumbnail';

/**
 * Search tab: natural-language smart search over server assets with a
 * 3-column result grid that opens the shared viewer.
 */
@ComponentV2
export struct SearchPage {
  @Param pathStack: NavPathStack = new NavPathStack();
  @Local keyword: string = '';
  @Local searching: boolean = false;
  @Local searched: boolean = false;
  @Local errorText: string = '';
  @Local results: ImmichAsset[] = [];

  build() {
    Column() {
      Text($r('app.string.tab_search'))
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.immich_text_primary'))
        .width('100%')
        .padding({ left: 16, top: 16, bottom: 12 })

      Row({ space: 8 }) {
        TextInput({ text: this.keyword, placeholder: $r('app.string.search_hint') })
          .onChange((value: string) => {
            this.keyword = value;
          })
          .onSubmit(() => {
            this.doSearch();
          })
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.immich_surface'))
          .borderRadius(12)
          .fontSize(14)
        Button($r('app.string.search_button'))
          .buttonStyle(ButtonStyleMode.EMPHASIZED)
          .backgroundColor($r('app.color.immich_primary'))
          .fontColor(Color.White)
          .height(40)
          .enabled(!this.searching)
          .onClick(() => {
            this.doSearch();
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12 })

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
              this.doSearch();
            })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.searching) {
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
      } else if (!this.searched) {
        Column({ space: 12 }) {
          Text($r('app.string.search_prompt'))
            .fontSize(14)
            .fontColor($r('app.color.immich_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 40, right: 40 })
      } else if (this.results.length === 0) {
        Column({ space: 12 }) {
          Text($r('app.string.search_empty'))
            .fontSize(14)
            .fontColor($r('app.color.immich_text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .padding({ left: 40, right: 40 })
      } else {
        Grid() {
          ForEach(this.results, (asset: ImmichAsset, index: number) => {
            GridItem() {
              Column() {
                AssetThumbnail({ asset: asset })
              }
              .aspectRatio(1)
            }
            .onClick(() => {
              this.openViewer(index);
            })
          }, (asset: ImmichAsset) => asset.id)
        }
        .columnsTemplate('1fr 1fr 1fr')
        .columnsGap(2)
        .rowsGap(2)
        .width('100%')
        .layoutWeight(1)
        .margin({ top: 12 })
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.immich_bg'))
  }

  private async doSearch(): Promise<void> {
    const keyword: string = this.keyword.trim();
    if (keyword.length === 0 || this.searching) {
      return;
    }
    this.searching = true;
    this.searched = true;
    this.errorText = '';
    try {
      this.results = await ImmichSearchApi.searchSmart(keyword, 1, 200);
    } catch (err) {
      this.results = [];
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.searching = false;
  }

  private openViewer(index: number): void {
    const param: string = JSON.stringify({ searchQuery: this.keyword.trim(), index: index });
    this.pathStack.pushPathByName('viewer', param, false);
  }
}
