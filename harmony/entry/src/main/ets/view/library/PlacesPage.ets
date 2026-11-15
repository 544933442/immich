import { MapComponent, map, mapCommon } from '@kit.MapKit';
import { AsyncCallback, BusinessError } from '@kit.BasicServicesKit';
import { ImmichApiError, ImmichMapApi, ImmichMapMarker } from 'network';

/**
 * Places map: one marker per geotagged asset from GET /map/markers.
 * Tapping a marker opens that asset in the full-screen viewer.
 */
@ComponentV2
export struct PlacesPage {
  @Local loading: boolean = false;
  @Local errorText: string = '';
  private pathStack: NavPathStack = new NavPathStack();
  private mapOptions: mapCommon.MapOptions = {
    position: {
      target: {
        latitude: 20,
        longitude: 10
      },
      zoom: 2
    }
  };
  private mapController: map.MapComponentController | null = null;
  private markersLoaded: boolean = false;
  private markerToAsset: Map<string, string> = new Map<string, string>();
  private mapCallback: AsyncCallback<map.MapComponentController> =
    (err: BusinessError, mapController: map.MapComponentController): void => {
      if (err) {
        return;
      }
      this.mapController = mapController;
      mapController.getEventManager().on('markerClick', (marker: map.Marker): void => {
        this.onMarkerClicked(marker.getId());
      });
      this.loadMarkers();
    };

  build() {
    NavDestination() {
      Stack() {
        MapComponent({
          mapOptions: this.mapOptions,
          mapCallback: this.mapCallback
        })
          .width('100%')
          .height('100%')

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
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.immich_surface'))
        }

        if (this.errorText.length > 0) {
          Column({ space: 10 }) {
            Text(this.errorText)
              .fontSize(13)
              .fontColor($r('app.color.immich_text_secondary'))
            Button($r('app.string.common_retry'))
              .buttonStyle(ButtonStyleMode.NORMAL)
              .controlSize(ControlSize.SMALL)
              .onClick(() => {
                this.loadMarkers();
              })
          }
          .padding(16)
          .borderRadius(14)
          .backgroundColor($r('app.color.immich_surface'))
        }
      }
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.library_places'))
    .backgroundColor($r('app.color.immich_bg'))
    .onReady((ctx: NavDestinationContext) => {
      this.pathStack = ctx.pathStack;
    })
  }

  private async loadMarkers(): Promise<void> {
    const controller: map.MapComponentController | null = this.mapController;
    if (this.markersLoaded || controller === null) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const markers: ImmichMapMarker[] = await ImmichMapApi.getMapMarkers();
      for (const entry of markers) {
        const options: mapCommon.MarkerOptions = {
          position: {
            latitude: entry.lat,
            longitude: entry.lon
          },
          clickable: true
        };
        const marker: map.Marker = await controller.addMarker(options);
        this.markerToAsset.set(marker.getId(), entry.id);
      }
      if (markers.length > 0) {
        const cameraPosition: mapCommon.CameraPosition = {
          target: {
            latitude: markers[0].lat,
            longitude: markers[0].lon
          },
          zoom: 10
        };
        controller.animateCamera(map.newCameraPosition(cameraPosition), 600);
      }
      this.markersLoaded = true;
    } catch (err) {
      this.errorText = err instanceof ImmichApiError ? err.message : 'network error';
    }
    this.loading = false;
  }

  private onMarkerClicked(markerId: string): void {
    const assetId: string | undefined = this.markerToAsset.get(markerId);
    if (assetId === undefined) {
      return;
    }
    const param: string = JSON.stringify({ assetId: assetId, index: 0 });
    this.pathStack.pushPathByName('viewer', param, false);
  }
}

/** Route-table builder for the "places" destination. */
@Builder
export function PlacesBuilder() {
  PlacesPage()
}
