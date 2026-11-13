import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { dataSharePredicates } from '@kit.ArkData';
import { ImmichSettings, LocalAssetRecord, UploadState } from 'data';

/** Pseudo folder URI that groups all media-library assets in the local DB. */
export const GALLERY_FOLDER_URI: string = 'mediastore://gallery';

/** One gallery album offered for backup exclusion. */
export class GalleryAlbumInfo {
  uri: string = '';
  name: string = '';
  count: number = 0;
}

/**
 * Scans the system media library (gallery) for photos and videos using the
 * restricted ohos.permission.READ_IMAGEVIDEO permission.
 */
export class GalleryMediaScanner {
  /**
   * Enumerate every image/video in the media library and map it to a local
   * asset record keyed by its stable media URI. Assets living in albums the
   * user excluded from backup are skipped.
   */
  static async scanGallery(context: Context): Promise<LocalAssetRecord[]> {
    const helper: photoAccessHelper.PhotoAccessHelper =
      photoAccessHelper.getPhotoAccessHelper(context);
    const predicates: dataSharePredicates.DataSharePredicates =
      new dataSharePredicates.DataSharePredicates();
    predicates.orderByDesc(photoAccessHelper.PhotoKeys.DATE_ADDED);
    const fetchOptions: photoAccessHelper.FetchOptions = {
      fetchColumns: ['display_name', 'title', 'size', 'date_modified'],
      predicates: predicates
    };
    const fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
      await helper.getAssets(fetchOptions);
    const excludedUris: Set<string> = await GalleryMediaScanner.collectExcludedAssetUris(context);
    const records: LocalAssetRecord[] = [];
    try {
      const assets: Array<photoAccessHelper.PhotoAsset> = await fetchResult.getAllObjects();
      for (const asset of assets) {
        if (excludedUris.size > 0 && excludedUris.has(asset.uri)) {
          continue;
        }
        const rec: LocalAssetRecord = new LocalAssetRecord();
        rec.uri = asset.uri;
        rec.path = asset.uri;
        // display_name carries the real filename with extension; title does not.
        rec.name = GalleryMediaScanner.nameOf(asset);
        rec.folderUri = GALLERY_FOLDER_URI;
        rec.size = GalleryMediaScanner.numberOr(asset, 'size', 0);
        rec.mtimeMs = GalleryMediaScanner.numberOr(asset, 'date_modified', 0) * 1000;
        rec.state = UploadState.PENDING;
        if (rec.name.length > 0 && rec.size > 0) {
          records.push(rec);
        }
      }
    } finally {
      fetchResult.close();
    }
    return records;
  }

  /**
   * List gallery albums the user can exclude from backup: user albums plus
   * the system video and image albums.
   */
  static async listGalleryAlbums(context: Context): Promise<GalleryAlbumInfo[]> {
    const helper: photoAccessHelper.PhotoAccessHelper =
      photoAccessHelper.getPhotoAccessHelper(context);
    const albums: photoAccessHelper.Album[] =
      await GalleryMediaScanner.fetchBackupAlbums(helper);
    const infos: GalleryAlbumInfo[] = [];
    for (const album of albums) {
      const info: GalleryAlbumInfo = new GalleryAlbumInfo();
      info.uri = album.albumUri;
      info.name = album.albumName;
      info.count = album.count;
      infos.push(info);
    }
    return infos;
  }

  /** URIs of all assets living in albums the user excluded from backup. */
  private static async collectExcludedAssetUris(context: Context): Promise<Set<string>> {
    const uris: Set<string> = new Set<string>();
    const excluded: string[] = ImmichSettings.getGalleryExcludedAlbums();
    if (excluded.length === 0) {
      return uris;
    }
    const helper: photoAccessHelper.PhotoAccessHelper =
      photoAccessHelper.getPhotoAccessHelper(context);
    const albums: photoAccessHelper.Album[] =
      await GalleryMediaScanner.fetchBackupAlbums(helper);
    for (const album of albums) {
      if (excluded.indexOf(album.albumUri) < 0) {
        continue;
      }
      const assets: Array<photoAccessHelper.PhotoAsset> =
        await GalleryMediaScanner.assetsOfAlbum(album);
      for (const asset of assets) {
        uris.add(asset.uri);
      }
    }
    return uris;
  }

  /** Enumerate excludable albums: user albums + system video/image albums. */
  private static async fetchBackupAlbums(
    helper: photoAccessHelper.PhotoAccessHelper): Promise<photoAccessHelper.Album[]> {
    const out: photoAccessHelper.Album[] = [];
    const user: photoAccessHelper.Album[] = await GalleryMediaScanner.fetchAlbumsOfType(helper,
      photoAccessHelper.AlbumType.USER, photoAccessHelper.AlbumSubtype.USER_GENERIC);
    const video: photoAccessHelper.Album[] = await GalleryMediaScanner.fetchAlbumsOfType(helper,
      photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.VIDEO);
    const image: photoAccessHelper.Album[] = await GalleryMediaScanner.fetchAlbumsOfType(helper,
      photoAccessHelper.AlbumType.SYSTEM, photoAccessHelper.AlbumSubtype.IMAGE);
    for (const album of user) {
      out.push(album);
    }
    for (const album of video) {
      out.push(album);
    }
    for (const album of image) {
      out.push(album);
    }
    return out;
  }

  private static async fetchAlbumsOfType(
    helper: photoAccessHelper.PhotoAccessHelper,
    type: photoAccessHelper.AlbumType,
    subtype: photoAccessHelper.AlbumSubtype): Promise<photoAccessHelper.Album[]> {
    try {
      const fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.Album> =
        await helper.getAlbums(type, subtype);
      try {
        return await fetchResult.getAllObjects();
      } finally {
        fetchResult.close();
      }
    } catch (err) {
      return [];
    }
  }

  private static async assetsOfAlbum(
    album: photoAccessHelper.Album): Promise<Array<photoAccessHelper.PhotoAsset>> {
    try {
      const predicates: dataSharePredicates.DataSharePredicates =
        new dataSharePredicates.DataSharePredicates();
      const fetchOptions: photoAccessHelper.FetchOptions = {
        fetchColumns: [],
        predicates: predicates
      };
      const fetchResult: photoAccessHelper.FetchResult<photoAccessHelper.PhotoAsset> =
        await album.getAssets(fetchOptions);
      try {
        return await fetchResult.getAllObjects();
      } finally {
        fetchResult.close();
      }
    } catch (err) {
      return [];
    }
  }

  /** Real filename with extension (display_name), falling back to title. */
  private static nameOf(asset: photoAccessHelper.PhotoAsset): string {
    const displayName: string = GalleryMediaScanner.stringOf(asset, 'display_name', '');
    if (displayName.length > 0) {
      return displayName;
    }
    return GalleryMediaScanner.stringOf(asset, 'title', '');
  }

  private static stringOf(asset: photoAccessHelper.PhotoAsset, key: string,
    fallback: string): string {
    try {
      const value: string | number | boolean = asset.get(key);
      return typeof value === 'string' ? value : fallback;
    } catch (err) {
      return fallback;
    }
  }

  private static numberOr(asset: photoAccessHelper.PhotoAsset, key: string,
    fallback: number): number {
    try {
      const value: string | number | boolean = asset.get(key);
      return typeof value === 'number' ? value : fallback;
    } catch (err) {
      return fallback;
    }
  }
}
