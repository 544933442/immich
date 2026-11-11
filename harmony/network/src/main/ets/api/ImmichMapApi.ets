import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { ImmichMapMarker, ImmichMapMarkerRaw } from '../model/ApiModels';

/** Server map APIs: geotagged asset markers for the Places map. */
export class ImmichMapApi {
  /** GET /map/markers — one marker per geotagged asset. */
  static async getMapMarkers(): Promise<ImmichMapMarker[]> {
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/map/markers');
    const raw: ImmichMapMarkerRaw[] = JSON.parse(text) as ImmichMapMarkerRaw[];
    const markers: ImmichMapMarker[] = [];
    for (const entry of raw) {
      const marker: ImmichMapMarker = new ImmichMapMarker();
      marker.id = entry.id;
      marker.lat = entry.lat;
      marker.lon = entry.lon;
      marker.city = entry.city ?? '';
      marker.state = entry.state ?? '';
      marker.country = entry.country ?? '';
      markers.push(marker);
    }
    return markers;
  }
}
