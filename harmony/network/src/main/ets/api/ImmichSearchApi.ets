import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { AssetResponseRaw, ImmichAsset, SearchResponseRaw } from '../model/ApiModels';

/** Body of POST /search/smart. */
export interface SmartSearchRequest {
  query: string;
  page: number;
  size: number;
  withExif: boolean;
}

/** Server smart search API (natural-language photo search). */
export class ImmichSearchApi {
  /**
   * POST /search/smart — natural language search. Page is 1-based and
   * deprecated server-side but still honored; used for viewer paging.
   */
  static async searchSmart(query: string, page: number, size: number): Promise<ImmichAsset[]> {
    const body: SmartSearchRequest = {
      query: query,
      page: page,
      size: size,
      withExif: false
    };
    const text: string =
      await ImmichHttpClient.requestJsonText(http.RequestMethod.POST, '/search/smart', body);
    const raw: SearchResponseRaw = JSON.parse(text) as SearchResponseRaw;
    const entries: AssetResponseRaw[] = raw.assets?.items ?? [];
    const assets: ImmichAsset[] = [];
    for (const entry of entries) {
      assets.push(ImmichAsset.fromResponseRaw(entry));
    }
    return assets;
  }
}
