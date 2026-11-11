import { fileIo } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface DiskCacheEntry {
  fileName: string;
  size: number;
  lastAccess: number;
}

/**
 * LRU disk cache for downloaded images, backed by a JSON manifest.
 */
export class ImageDiskCache {
  private baseDir: string = '';
  private manifestPath: string = '';
  private maxBytes: number = 0;
  private index: Map<string, DiskCacheEntry> = new Map<string, DiskCacheEntry>();
  private totalBytes: number = 0;

  private constructor() {
  }

  static async create(context: Context, name: string, maxBytes: number): Promise<ImageDiskCache> {
    const cache: ImageDiskCache = new ImageDiskCache();
    cache.baseDir = `${context.cacheDir}/${name}`;
    cache.manifestPath = `${cache.baseDir}/manifest.json`;
    cache.maxBytes = maxBytes;
    try {
      if (!fileIo.accessSync(cache.baseDir)) {
        fileIo.mkdirSync(cache.baseDir, true);
      }
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      throw new Error(`create cache dir failed: ${error.message}`);
    }
    cache.loadManifest();
    cache.validateEntries();
    return cache;
  }

  /** Returns the local file path for the key, or null on miss. */
  get(key: string): string | null {
    const entry: DiskCacheEntry | undefined = this.index.get(key);
    if (entry === undefined) {
      return null;
    }
    const path: string = `${this.baseDir}/${entry.fileName}`;
    try {
      if (!fileIo.accessSync(path)) {
        this.index.delete(key);
        this.totalBytes -= entry.size;
        this.saveManifest();
        return null;
      }
    } catch (err) {
      return null;
    }
    entry.lastAccess = Date.now();
    this.saveManifest();
    return path;
  }

  put(key: string, data: ArrayBuffer): void {
    const fileName: string = ImageDiskCache.hashKey(key);
    const path: string = `${this.baseDir}/${fileName}`;
    try {
      if (!fileIo.accessSync(path)) {
        const file: fileIo.File =
          fileIo.openSync(path, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE);
        try {
          fileIo.writeSync(file.fd, data);
        } finally {
          fileIo.closeSync(file);
        }
      }
    } catch (err) {
      return;
    }
    const entry: DiskCacheEntry = { fileName: fileName, size: data.byteLength, lastAccess: Date.now() };
    this.totalBytes += entry.size;
    this.index.set(key, entry);
    this.evictIfNeeded();
    this.saveManifest();
  }

  /** Total bytes currently held by the cache. */
  sizeBytes(): number {
    return this.totalBytes;
  }

  clear(): void {
    this.index.forEach((entry: DiskCacheEntry): void => {
      try {
        const path: string = `${this.baseDir}/${entry.fileName}`;
        if (fileIo.accessSync(path)) {
          fileIo.unlinkSync(path);
        }
      } catch (err) {
        // ignore individual removal errors
      }
    });
    this.index.clear();
    this.totalBytes = 0;
    this.saveManifest();
  }

  private evictIfNeeded(): void {
    if (this.totalBytes <= this.maxBytes) {
      return;
    }
    const sorted: string[] = Array.from(this.index.keys()).sort((a: string, b: string): number => {
      const ea: DiskCacheEntry | undefined = this.index.get(a);
      const eb: DiskCacheEntry | undefined = this.index.get(b);
      const ta: number = ea === undefined ? 0 : ea.lastAccess;
      const tb: number = eb === undefined ? 0 : eb.lastAccess;
      return ta - tb;
    });
    for (const key of sorted) {
      if (this.totalBytes <= this.maxBytes * 0.9) {
        break;
      }
      const entry: DiskCacheEntry | undefined = this.index.get(key);
      if (entry === undefined) {
        continue;
      }
      try {
        const path: string = `${this.baseDir}/${entry.fileName}`;
        if (fileIo.accessSync(path)) {
          fileIo.unlinkSync(path);
        }
      } catch (err) {
        // ignore
      }
      this.totalBytes -= entry.size;
      this.index.delete(key);
    }
  }

  private loadManifest(): void {
    try {
      if (!fileIo.accessSync(this.manifestPath)) {
        return;
      }
      const raw: string = fileIo.readTextSync(this.manifestPath);
      const parsed: Record<string, DiskCacheEntry> = JSON.parse(raw) as Record<string, DiskCacheEntry>;
      const keys: string[] = Object.keys(parsed);
      for (const key of keys) {
        const entry: DiskCacheEntry = parsed[key];
        this.index.set(key, entry);
        this.totalBytes += entry.size;
      }
    } catch (err) {
      this.index.clear();
      this.totalBytes = 0;
    }
  }

  private validateEntries(): void {
    const keys: string[] = Array.from(this.index.keys());
    for (const key of keys) {
      const entry: DiskCacheEntry | undefined = this.index.get(key);
      if (entry === undefined) {
        continue;
      }
      const path: string = `${this.baseDir}/${entry.fileName}`;
      try {
        if (!fileIo.accessSync(path)) {
          this.index.delete(key);
          this.totalBytes -= entry.size;
        }
      } catch (err) {
        this.index.delete(key);
        this.totalBytes -= entry.size;
      }
    }
  }

  private saveManifest(): void {
    try {
      const snapshot: Record<string, DiskCacheEntry> = {};
      this.index.forEach((entry: DiskCacheEntry, key: string): void => {
        snapshot[key] = entry;
      });
      const file: fileIo.File =
        fileIo.openSync(this.manifestPath, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      try {
        fileIo.writeSync(file.fd, JSON.stringify(snapshot));
      } finally {
        fileIo.closeSync(file);
      }
    } catch (err) {
      // manifest persistence is best-effort
    }
  }

  private static hashKey(key: string): string {
    let hash: number = 5381;
    for (let i = 0; i < key.length; i++) {
      hash = ((hash << 5) + hash + key.charCodeAt(i)) >>> 0;
    }
    return `${hash.toString(16)}_${key.length}`;
  }
}
