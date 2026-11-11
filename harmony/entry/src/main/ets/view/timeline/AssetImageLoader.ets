import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ImageDiskCache, ThumbHash, ThumbHashImage } from 'commons';
import { ImmichAsset, ImmichAssetApi, ImmichPeopleApi } from 'network';

/**
 * Three-tier image loader for server assets:
 * in-memory PixelMap cache -> disk cache -> authorized network download.
 */
export class AssetImageLoader {
  private static readonly MEM_CACHE_LIMIT: number = 300;
  private static thumbs: ImageDiskCache | null = null;
  private static previews: ImageDiskCache | null = null;
  private static videos: ImageDiskCache | null = null;
  private static mem: Map<string, PixelMap> = new Map<string, PixelMap>();
  private static inflight: Map<string, Promise<PixelMap>> = new Map<string, Promise<PixelMap>>();
  private static videoInflight: Map<string, Promise<string>> = new Map<string, Promise<string>>();

  static async init(context: Context): Promise<void> {
    if (AssetImageLoader.thumbs === null) {
      AssetImageLoader.thumbs = await ImageDiskCache.create(context, 'thumbs', 128 * 1024 * 1024);
    }
    if (AssetImageLoader.previews === null) {
      AssetImageLoader.previews = await ImageDiskCache.create(context, 'previews', 256 * 1024 * 1024);
    }
    if (AssetImageLoader.videos === null) {
      AssetImageLoader.videos = await ImageDiskCache.create(context, 'videos', 512 * 1024 * 1024);
    }
  }

  /** Grid thumbnail (small square-ish render). */
  static async loadThumbnail(asset: ImmichAsset): Promise<PixelMap> {
    return AssetImageLoader.loadThumbnailById(asset.id);
  }

  /** Grid thumbnail by asset id (album covers etc.). */
  static async loadThumbnailById(id: string): Promise<PixelMap> {
    const key: string = `thumb_${id}`;
    return AssetImageLoader.load(key, id, 'thumbnail', AssetImageLoader.thumbs!);
  }

  /** Full-width preview for the viewer. */
  static async loadPreview(asset: ImmichAsset): Promise<PixelMap> {
    const key: string = `preview_${asset.id}`;
    return AssetImageLoader.load(key, asset.id, 'preview', AssetImageLoader.previews!);
  }

  /** Decode the asset's thumbhash into a blur placeholder PixelMap. */
  static async thumbhashPixelMap(asset: ImmichAsset): Promise<PixelMap | null> {
    if (asset.thumbhash.length === 0) {
      return null;
    }
    const key: string = `ph_${asset.id}`;
    const hit: PixelMap | undefined = AssetImageLoader.mem.get(key);
    if (hit !== undefined) {
      return hit;
    }
    try {
      const helper: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = helper.decodeSync(asset.thumbhash);
      const decoded: ThumbHashImage = ThumbHash.thumbHashToRGBA(bytes);
      const buffer: ArrayBuffer = new ArrayBuffer(decoded.rgba.length);
      new Uint8Array(buffer).set(decoded.rgba);
      const opts: image.InitializationOptions = {
        size: { width: decoded.width, height: decoded.height },
        srcPixelFormat: image.PixelMapFormat.RGBA_8888,
        pixelFormat: image.PixelMapFormat.RGBA_8888
      };
      const pm: PixelMap = await image.createPixelMap(buffer, opts);
      AssetImageLoader.remember(key, pm);
      return pm;
    } catch (err) {
      return null;
    }
  }

  /** Download a video original to the cache; returns the local file path. */
  static async loadVideoFile(asset: ImmichAsset): Promise<string> {
    const key: string = `video_${asset.id}`;
    const cache: ImageDiskCache = AssetImageLoader.videos!;
    const existing: string | null = cache.get(key);
    if (existing !== null) {
      return existing;
    }
    const pending: Promise<string> | undefined = AssetImageLoader.videoInflight.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<string> = new Promise<string>((resolve, reject): void => {
      ImmichAssetApi.downloadAsset(asset.id, 'original').then((buffer: ArrayBuffer): void => {
        cache.put(key, buffer);
        const path: string | null = cache.get(key);
        if (path === null) {
          reject(new Error('video cache write failed'));
          return;
        }
        resolve(path);
      }).catch((err: Error): void => {
        reject(err);
      });
    });
    AssetImageLoader.videoInflight.set(key, task);
    try {
      return await task;
    } finally {
      AssetImageLoader.videoInflight.delete(key);
    }
  }

  private static async load(cacheKey: string, assetId: string, size: string,
    cache: ImageDiskCache): Promise<PixelMap> {
    const memHit: PixelMap | undefined = AssetImageLoader.mem.get(cacheKey);
    if (memHit !== undefined) {
      return memHit;
    }
    const pending: Promise<PixelMap> | undefined = AssetImageLoader.inflight.get(cacheKey);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<PixelMap> = AssetImageLoader.fetch(cacheKey, assetId, size, cache);
    AssetImageLoader.inflight.set(cacheKey, task);
    try {
      return await task;
    } finally {
      AssetImageLoader.inflight.delete(cacheKey);
    }
  }

  /** Person face avatar from /people/{id}/thumbnail. */
  static async loadPersonAvatar(personId: string): Promise<PixelMap> {
    const key: string = `person_${personId}`;
    const memHit: PixelMap | undefined = AssetImageLoader.mem.get(key);
    if (memHit !== undefined) {
      return memHit;
    }
    const pending: Promise<PixelMap> | undefined = AssetImageLoader.inflight.get(key);
    if (pending !== undefined) {
      return pending;
    }
    const task: Promise<PixelMap> = AssetImageLoader.fetchByEndpoint(key,
      (): Promise<ArrayBuffer> => ImmichPeopleApi.downloadPersonThumbnail(personId),
      AssetImageLoader.thumbs!);
    AssetImageLoader.inflight.set(key, task);
    try {
      return await task;
    } finally {
      AssetImageLoader.inflight.delete(key);
    }
  }

  private static async fetchByEndpoint(cacheKey: string, download: () => Promise<ArrayBuffer>,
    cache: ImageDiskCache): Promise<PixelMap> {
    const diskPath: string | null = cache.get(cacheKey);
    if (diskPath !== null) {
      try {
        const pm: PixelMap = await AssetImageLoader.decodeFile(diskPath);
        AssetImageLoader.remember(cacheKey, pm);
        return pm;
      } catch (err) {
        // fall through to network
      }
    }
    const buffer: ArrayBuffer = await download();
    cache.put(cacheKey, buffer);
    const pm: PixelMap = await AssetImageLoader.decodeBuffer(buffer);
    AssetImageLoader.remember(cacheKey, pm);
    return pm;
  }

  private static async fetch(cacheKey: string, assetId: string, size: string,
    cache: ImageDiskCache): Promise<PixelMap> {
    const diskPath: string | null = cache.get(cacheKey);
    if (diskPath !== null) {
      try {
        const pm: PixelMap = await AssetImageLoader.decodeFile(diskPath);
        AssetImageLoader.remember(cacheKey, pm);
        return pm;
      } catch (err) {
        // fall through to network
      }
    }
    const buffer: ArrayBuffer = await ImmichAssetApi.downloadAsset(assetId, size);
    cache.put(cacheKey, buffer);
    const pm: PixelMap = await AssetImageLoader.decodeBuffer(buffer);
    AssetImageLoader.remember(cacheKey, pm);
    return pm;
  }

  private static async decodeFile(path: string): Promise<PixelMap> {
    const source: image.ImageSource = image.createImageSource(path);
    try {
      return await source.createPixelMap();
    } finally {
      source.release();
    }
  }

  private static async decodeBuffer(buffer: ArrayBuffer): Promise<PixelMap> {
    const source: image.ImageSource = image.createImageSource(buffer);
    try {
      return await source.createPixelMap();
    } finally {
      source.release();
    }
  }

  private static remember(key: string, pm: PixelMap): void {
    if (AssetImageLoader.mem.size >= AssetImageLoader.MEM_CACHE_LIMIT) {
      const oldest: string | null = AssetImageLoader.mem.keys().next().value ?? null;
      if (oldest !== null) {
        const evicted: PixelMap | undefined = AssetImageLoader.mem.get(oldest);
        AssetImageLoader.mem.delete(oldest);
        if (evicted !== undefined) {
          evicted.release();
        }
      }
    }
    AssetImageLoader.mem.set(key, pm);
  }
}
