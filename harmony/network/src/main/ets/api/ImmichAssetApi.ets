import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import {
  ImmichApiError,
  ImmichAsset,
  ImmichBucket,
  ImmichBucketColumnsRaw,
  ImmichBucketCountRaw,
  AssetResponseRaw,
  ImmichUploadResponseRaw,
  ImmichUploadResult,
  TimelineQuery
} from '../model/ApiModels';

/** Body of PUT /assets (bulk favorite). */
export interface BulkFavoriteRequest {
  ids: string[];
  isFavorite: boolean;
}

/** Body of PUT /assets (bulk visibility change, e.g. archive). */
export interface BulkVisibilityRequest {
  ids: string[];
  visibility: string;
}

/** Body of DELETE /assets (bulk trash). */
export interface BulkDeleteRequest {
  ids: string[];
  force: boolean;
}

/** Metadata of a local file to upload. */
export class UploadAssetRequest {
  filePath: string = '';
  fileName: string = '';
  contentType: string = 'application/octet-stream';
  deviceAssetId: string = '';
  deviceId: string = '';
  fileCreatedAtIso: string = '';
  fileModifiedAtIso: string = '';
  isFavorite: boolean = false;
  durationMs: number = 0;
}

/** Server asset APIs: timeline buckets, media download, upload and mutations. */
export class ImmichAssetApi {
  /** GET /timeline/buckets — monthly buckets with counts, newest first. */
  static async getTimeBuckets(query?: TimelineQuery): Promise<ImmichBucket[]> {
    const prefix: string = query !== undefined ? query.toQueryPrefix() : '';
    const text: string =
      await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, `/timeline/buckets?${prefix}order=desc`);
    const raw: ImmichBucketCountRaw[] = JSON.parse(text) as ImmichBucketCountRaw[];
    const buckets: ImmichBucket[] = [];
    for (const entry of raw) {
      const bucket: ImmichBucket = new ImmichBucket();
      bucket.timeBucket = entry.timeBucket;
      bucket.count = entry.count;
      buckets.push(bucket);
    }
    return buckets;
  }

  /** GET /timeline/bucket — assets of one monthly bucket (columnar response). */
  static async getTimeBucketAssets(timeBucket: string, query?: TimelineQuery): Promise<ImmichAsset[]> {
    const prefix: string = query !== undefined ? query.toQueryPrefix() : '';
    const path: string = `/timeline/bucket?${prefix}timeBucket=${encodeURIComponent(timeBucket)}&order=desc`;
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, path);
    const cols: ImmichBucketColumnsRaw = JSON.parse(text) as ImmichBucketColumnsRaw;
    const ids: string[] = cols.id ?? [];
    const assets: ImmichAsset[] = [];
    for (let i = 0; i < ids.length; i++) {
      const asset: ImmichAsset = new ImmichAsset();
      asset.id = ids[i];
      const ratio: number | null | undefined = cols.ratio !== undefined ? cols.ratio[i] : undefined;
      asset.ratio = ratio === null || ratio === undefined || ratio <= 0 ? 1 : ratio;
      const thumbhash: string | null | undefined =
        cols.thumbhash !== undefined ? cols.thumbhash[i] : undefined;
      asset.thumbhash = thumbhash === null || thumbhash === undefined ? '' : thumbhash;
      asset.isImage = cols.isImage !== undefined ? cols.isImage[i] : true;
      asset.isFavorite = cols.isFavorite !== undefined ? cols.isFavorite[i] : false;
      asset.isTrashed = cols.isTrashed !== undefined ? cols.isTrashed[i] : false;
      asset.fileCreatedAt = cols.fileCreatedAt !== undefined ? (cols.fileCreatedAt[i] ?? '') : '';
      const duration: number | null | undefined = cols.duration !== undefined ? cols.duration[i] : undefined;
      asset.durationMs = duration === null || duration === undefined ? 0 : duration;
      const livePhoto: string | null | undefined =
        cols.livePhotoVideoId !== undefined ? cols.livePhotoVideoId[i] : undefined;
      asset.livePhotoVideoId = livePhoto === null || livePhoto === undefined ? '' : livePhoto;
      asset.visibility = cols.visibility !== undefined ? (cols.visibility[i] ?? 'timeline') : 'timeline';
      assets.push(asset);
    }
    return assets;
  }

  /** Download the rendered thumbnail/preview/original of an asset. */
  static async downloadAsset(id: string, size: string): Promise<ArrayBuffer> {
    const path: string = `/assets/${id}/thumbnail?size=${size}`;
    return ImmichHttpClient.requestBinary(http.RequestMethod.GET, path);
  }

  /** Toggle favorite flag for a set of assets (PUT /assets). */
  static async setFavorite(ids: string[], isFavorite: boolean): Promise<void> {
    const body: BulkFavoriteRequest = { ids: ids, isFavorite: isFavorite };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.PUT, '/assets', body);
  }

  /** Archive or restore a set of assets (PUT /assets visibility). */
  static async setArchived(ids: string[], archived: boolean): Promise<void> {
    const body: BulkVisibilityRequest = {
      ids: ids,
      visibility: archived ? 'archive' : 'timeline'
    };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.PUT, '/assets', body);
  }

  /** GET /assets/{id} — single asset with full metadata. */
  static async getAssetById(id: string): Promise<ImmichAsset> {
    const text: string =
      await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, `/assets/${id}`);
    const raw: AssetResponseRaw = JSON.parse(text) as AssetResponseRaw;
    return ImmichAsset.fromResponseRaw(raw);
  }

  /** Move assets to trash (DELETE /assets with force=false). */
  static async deleteAssets(ids: string[], force: boolean): Promise<void> {
    const body: BulkDeleteRequest = { ids: ids, force: force };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.DELETE, '/assets', body);
  }

  /**
   * Upload one local file (POST /assets multipart).
   * Fields mirror the Immich mobile app: deviceAssetId/deviceId are kept for
   * compatibility with servers <= v2.7.5; current servers rely on the
   * fileCreatedAt/fileModifiedAt/visibility fields.
   */
  static async uploadAsset(request: UploadAssetRequest,
    onProgress?: (sent: number, total: number) => void): Promise<ImmichUploadResult> {
    const fields: Record<string, string> = {
      'deviceAssetId': request.deviceAssetId,
      'deviceId': request.deviceId,
      'fileCreatedAt': request.fileCreatedAtIso,
      'fileModifiedAt': request.fileModifiedAtIso,
      'isFavorite': request.isFavorite ? 'true' : 'false',
      'duration': `${request.durationMs}`
    };
    const text: string = await ImmichHttpClient.uploadMultipart('/assets', fields, 'assetData',
      request.fileName, request.filePath, request.contentType, onProgress);
    const raw: ImmichUploadResponseRaw = JSON.parse(text) as ImmichUploadResponseRaw;
    const result: ImmichUploadResult = new ImmichUploadResult();
    result.id = raw.id;
    if (raw.status !== undefined) {
      result.status = raw.status;
    } else if (raw.duplicate !== undefined && raw.duplicate) {
      result.status = 'duplicate';
    }
    return result;
  }
}
