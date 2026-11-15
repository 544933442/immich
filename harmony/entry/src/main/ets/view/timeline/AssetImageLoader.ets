import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { ImageDiskCache, ThumbHash, ThumbHashImage } from 'commons';
import { ImmichAsset, ImmichAssetApi, ImmichPeopleApi } from 'network';

/** Cancelable handle for a queued thumbnail load. */
export class ThumbJob {
  readonly assetId: string;
  private cancelled: boolean = false;
  private onLoaded: (pm: PixelMap) => void;
  private onFailed: (err: Error) => void;

  constructor(assetId: string, onLoaded: (pm: PixelMap) => void, onFailed: (err: Error) => void) {
    this.assetId = assetId;
    this.onLoaded = onLoaded;
    this.onFailed = onFailed;
  }

  /** Stop the job if it has not delivered yet (in-flight downloads still finish and cache). */
  cancel(): void {
    this.cancelled = true;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  deliver(pm: PixelMap): void {
    if (!this.cancelled) {
      this.onLoaded(pm);
    }
  }

  fail(err: Error): void {
    if (!this.cancelled) {
      this.onFailed(err);
    }
  }
}

/**
 * Three-tier image loader for server assets:
 * in-memory PixelMap cache -> disk cache -> authorized network download.
 * Thumbnail loads run through a bounded-concurrency queue so fast scrolling
 * over huge libraries cannot trigger request or decode storms.
 */
export class AssetImageLoader {
  private static readonly MEM_CACHE_LIMIT: number = 300;
  private static readonly PH_CACHE_LIMIT: number = 600;
  private static readonly MAX_THUMB_CONCURRENCY: number = 6;
  private static thumbs: ImageDiskCache | null = null;
  private static previews: ImageDiskCache | null = null;
  private static videos: ImageDiskCache | null = null;
  private static originals: ImageDiskCache | null = null;
  private static mem: Map<string, PixelMap> = new Map<string, PixelMap>();
  private static ph: Map<string, PixelMap> = new Map<string, PixelMap>();
  private static inflight: Map<string, Promise<PixelMap>> = new Map<string, Promise<PixelMap>>();
  private static videoInflight: Map<string, Promise<string>> = new Map<string, Promise<string>>();
  private static thumbQueue: ThumbJob[] = [];
  private static activeThumbs: number = 0;

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
    if (AssetImageLoader.originals === null) {
      AssetImageLoader.originals = await ImageDiskCache.create(context, 'originals', 1024 * 1024 * 1024);
    }
  }

  /** Grid thumbnail (small square-ish render). */
  static async loadThumbnail(asset: ImmichAsset): Promise<PixelMap> {
    return AssetImageLoader.loadThumbnailById(asset.id);
  }

  /** Grid thumbnail by asset id (album covers etc.). */
  static async loadThumbnailById(id: string): Promise<PixelMap> {
    return new Promise<PixelMap>((resolve, reject): void => {
      AssetImageLoader.requestThumbnailById(id, resolve, reject);
    });
  }

  /** Queue a grid thumbnail load for an on-screen cell; cancel it when the cell goes off-screen. */
  static requestThumbnail(asset: ImmichAsset, onLoaded: (pm: PixelMap) => void,
    onFailed: (err: Error) => void): ThumbJob {
    return AssetImageLoader.requestThumbnailById(asset.id, onLoaded, onFailed);
  }

  /** Queue a thumbnail load by asset id, bounded by MAX_THUMB_CONCURRENCY. */
  static requestThumbnailById(id: string, onLoaded: (pm: PixelMap) => void,
    onFailed: (err: Error) => void): ThumbJob {
    const job: ThumbJob = new ThumbJob(id, onLoaded, onFailed);
    AssetImageLoader.thumbQueue.push(job);
    AssetImageLoader.pumpThumbs();
    return job;
  }

  private static pumpThumbs(): void {
    while (AssetImageLoader.activeThumbs < AssetImageLoader.MAX_THUMB_CONCURRENCY) {
      const job: ThumbJob | undefined = AssetImageLoader.thumbQueue.shift();
      if (job === undefined) {
        break;
      }
      if (job.isCancelled()) {
        continue;
      }
      AssetImageLoader.activeThumbs++;
      const key: string = `thumb_${job.assetId}`;
      AssetImageLoader.load(key, job.assetId, 'thumbnail', AssetImageLoader.thumbs!)
        .then((pm: PixelMap): void => {
          job.deliver(pm);
        })
        .catch((err: Error): void => {
          job.fail(err);
        })
        .finally((): void => {
          AssetImageLoader.activeThumbs--;
          AssetImageLoader.pumpThumbs();
        });
    }
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
    const hit: PixelMap | undefined = AssetImageLoader.ph.get(key);
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
      AssetImageLoader.rememberPh(key, pm);
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

  /** Local path of the cached image original, or null when not downloaded. */
  static originalPathIfCached(asset: ImmichAsset): string | null {
    const cache: ImageDiskCache | null = AssetImageLoader.originals;
    if (cache === null) {
      return null;
    }
    return cache.get(`original_${asset.id}`);
  }

  /** Local path of the cached video file, or null when not downloaded. */
  static videoPathIfCached(asset: ImmichAsset): string | null {
    const cache: ImageDiskCache | null = AssetImageLoader.videos;
    if (cache === null) {
      return null;
    }
    return cache.get(`video_${asset.id}`);
  }

  /** True when the asset original is available offline. */
  static isAvailableOffline(asset: ImmichAsset): boolean {
    if (!asset.isImage) {
      return AssetImageLoader.videoPathIfCached(asset) !== null;
    }
    return AssetImageLoader.originalPathIfCached(asset) !== null;
  }

  /** Download (or reuse) the original file for offline use; returns the local path. */
  static async downloadOriginal(asset: ImmichAsset): Promise<string> {
    if (!asset.isImage) {
      return AssetImageLoader.loadVideoFile(asset);
    }
    const key: string = `original_${asset.id}`;
    const cache: ImageDiskCache = AssetImageLoader.originals!;
    const existing: string | null = cache.get(key);
    if (existing !== null) {
      return existing;
    }
    const buffer: ArrayBuffer = await ImmichAssetApi.downloadAsset(asset.id, 'original');
    cache.put(key, buffer);
    const path: string | null = cache.get(key);
    if (path === null) {
      throw new Error('original cache write failed');
    }
    return path;
  }

  /** Total bytes held by all disk caches (0 before init). */
  static totalCacheBytes(): number {
    let total: number = 0;
    if (AssetImageLoader.thumbs !== null) {
      total += AssetImageLoader.thumbs.sizeBytes();
    }
    if (AssetImageLoader.previews !== null) {
      total += AssetImageLoader.previews.sizeBytes();
    }
    if (AssetImageLoader.videos !== null) {
      total += AssetImageLoader.videos.sizeBytes();
    }
    if (AssetImageLoader.originals !== null) {
      total += AssetImageLoader.originals.sizeBytes();
    }
    return total;
  }

  /** Wipe every disk cache and release in-memory pixel maps. */
  static clearAllCaches(): void {
    if (AssetImageLoader.thumbs !== null) {
      AssetImageLoader.thumbs.clear();
    }
    if (AssetImageLoader.previews !== null) {
      AssetImageLoader.previews.clear();
    }
    if (AssetImageLoader.videos !== null) {
      AssetImageLoader.videos.clear();
    }
    if (AssetImageLoader.originals !== null) {
      AssetImageLoader.originals.clear();
    }
    AssetImageLoader.mem.forEach((pm: PixelMap): void => {
      pm.release();
    });
    AssetImageLoader.mem.clear();
    AssetImageLoader.ph.forEach((pm: PixelMap): void => {
      pm.release();
    });
    AssetImageLoader.ph.clear();
  }

  private static async load(cacheKey: string, assetId: string, size: string,
    cache: ImageDiskCache): Promise<PixelMap> {
    const memHit: PixelMap | undefined = AssetImageLoader.mem.get(cacheKey);
    if (memHit !== undefined) {
      // LRU touch: refresh insertion order so recently shown cells survive eviction.
      AssetImageLoader.mem.delete(cacheKey);
      AssetImageLoader.mem.set(cacheKey, memHit);
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
      AssetImageLoader.mem.delete(key);
      AssetImageLoader.mem.set(key, memHit);
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

  private static rememberPh(key: string, pm: PixelMap): void {
    if (AssetImageLoader.ph.size >= AssetImageLoader.PH_CACHE_LIMIT) {
      const oldest: string | null = AssetImageLoader.ph.keys().next().value ?? null;
      if (oldest !== null) {
        const evicted: PixelMap | undefined = AssetImageLoader.ph.get(oldest);
        AssetImageLoader.ph.delete(oldest);
        if (evicted !== undefined) {
          evicted.release();
        }
      }
    }
    AssetImageLoader.ph.set(key, pm);
  }
}
