/** Raw shape of POST /auth/login response (subset used by the app). */
export interface ImmichLoginResponseRaw {
  accessToken: string;
  userId: string;
  userEmail: string;
  name: string;
  isAdmin: boolean;
  profileImagePath: string;
  shouldChangePassword: boolean;
  isOnboarded: boolean;
}

/** Raw shape of GET /server/ping response. */
export interface ImmichPingRaw {
  res: string;
}

/** Raw shape of POST /auth/validateToken response. */
export interface ImmichValidateTokenRaw {
  authStatus: boolean;
}

/** Raw shape of GET /users/me response (subset used by the app). */
export interface ImmichUserRaw {
  id: string;
  name: string;
  email: string;
  profileImagePath: string;
}

/** Raw shape of one entry of GET /timeline/buckets response. */
export interface ImmichBucketCountRaw {
  timeBucket: string;
  count: number;
}

/**
 * Raw columnar shape of GET /timeline/bucket response. Each field is a
 * parallel array; entries may be null.
 */
export interface ImmichBucketColumnsRaw {
  id?: string[];
  ratio?: (number | null)[];
  thumbhash?: (string | null)[];
  isImage?: boolean[];
  isFavorite?: boolean[];
  isTrashed?: boolean[];
  fileCreatedAt?: string[];
  createdAt?: string[];
  duration?: (number | null)[];
  livePhotoVideoId?: (string | null)[];
  visibility?: string[];
}

/** Raw shape of POST /assets (upload) response, covering current and legacy servers. */
export interface ImmichUploadResponseRaw {
  id: string;
  status?: string;
  duplicate?: boolean;
}

/** Raw JSON shape of a timeline query (used in route params). */
export interface TimelineQueryRaw {
  albumId?: string;
  personId?: string;
  isFavorite?: boolean;
  isTrashed?: boolean;
  visibility?: string;
}

/** Raw shape of one full AssetResponseDto entry (search/memories responses). */
export interface AssetResponseRaw {
  id: string;
  thumbhash?: string | null;
  type?: string;
  duration?: number | null;
  fileCreatedAt?: string;
  isFavorite?: boolean;
  isTrashed?: boolean;
  livePhotoVideoId?: string | null;
  width?: number | null;
  height?: number | null;
  visibility?: string;
}

/** Raw shape of the "assets" facet of GET/POST /search responses. */
export interface SearchAssetsRaw {
  total?: number;
  count?: number;
  items?: AssetResponseRaw[];
  nextPage?: number | null;
  nextCursor?: string | null;
}

/** Raw shape of /search/smart response. */
export interface SearchResponseRaw {
  assets?: SearchAssetsRaw;
}

/** Raw shape of one PersonResponseDto entry. */
export interface ImmichPersonRaw {
  id: string;
  name?: string;
  isHidden?: boolean;
}

/** Raw shape of GET /people response. */
export interface PeopleResponseRaw {
  people?: ImmichPersonRaw[];
  total?: number;
}

/** Raw shape of MemoryDataDto. */
export interface MemoryDataRaw {
  year?: number;
  personName?: string;
}

/** Raw shape of one MemoryResponseDto entry. */
export interface ImmichMemoryRaw {
  id: string;
  type?: string;
  data?: MemoryDataRaw;
  assets?: AssetResponseRaw[];
}

/** Raw shape of one entry of GET /albums response (subset used by the app). */
export interface ImmichAlbumRaw {
  id: string;
  albumName: string;
  description?: string;
  albumThumbnailAssetId?: string;
  assetCount?: number;
  startDate?: string;
  endDate?: string;
}

/**
 * Server-side asset filter applied to /timeline/buckets and /timeline/bucket.
 * Mirrors the query parameters supported by the Immich timeline API.
 */
export class TimelineQuery {
  albumId?: string;
  personId?: string;
  isFavorite?: boolean;
  isTrashed?: boolean;
  visibility?: string;

  static allPhotos(): TimelineQuery {
    return new TimelineQuery();
  }

  static favorites(): TimelineQuery {
    const query: TimelineQuery = new TimelineQuery();
    query.isFavorite = true;
    return query;
  }

  static trash(): TimelineQuery {
    const query: TimelineQuery = new TimelineQuery();
    query.isTrashed = true;
    return query;
  }

  static fromRaw(raw?: TimelineQueryRaw): TimelineQuery {
    const query: TimelineQuery = new TimelineQuery();
    if (raw === undefined || raw === null) {
      return query;
    }
    if (raw.albumId !== undefined && raw.albumId !== null && raw.albumId.length > 0) {
      query.albumId = raw.albumId;
    }
    if (raw.personId !== undefined && raw.personId !== null && raw.personId.length > 0) {
      query.personId = raw.personId;
    }
    if (raw.isFavorite !== undefined && raw.isFavorite !== null) {
      query.isFavorite = raw.isFavorite;
    }
    if (raw.isTrashed !== undefined && raw.isTrashed !== null) {
      query.isTrashed = raw.isTrashed;
    }
    if (raw.visibility !== undefined && raw.visibility !== null && raw.visibility.length > 0) {
      query.visibility = raw.visibility;
    }
    return query;
  }

  toRaw(): TimelineQueryRaw {
    const raw: TimelineQueryRaw = {};
    if (this.albumId !== undefined) {
      raw.albumId = this.albumId;
    }
    if (this.personId !== undefined) {
      raw.personId = this.personId;
    }
    if (this.isFavorite !== undefined) {
      raw.isFavorite = this.isFavorite;
    }
    if (this.isTrashed !== undefined) {
      raw.isTrashed = this.isTrashed;
    }
    if (this.visibility !== undefined) {
      raw.visibility = this.visibility;
    }
    return raw;
  }

  /** Serialized extra query params, ending with '&' when non-empty. */
  toQueryPrefix(): string {
    const parts: string[] = [];
    if (this.albumId !== undefined) {
      parts.push(`albumId=${encodeURIComponent(this.albumId)}`);
    }
    if (this.personId !== undefined) {
      parts.push(`personId=${encodeURIComponent(this.personId)}`);
    }
    if (this.isFavorite !== undefined) {
      parts.push(`isFavorite=${this.isFavorite}`);
    }
    if (this.isTrashed !== undefined) {
      parts.push(`isTrashed=${this.isTrashed}`);
    }
    if (this.visibility !== undefined) {
      parts.push(`visibility=${this.visibility}`);
    }
    return parts.length > 0 ? `${parts.join('&')}&` : '';
  }
}

/** One monthly timeline bucket with its asset count. */
export class ImmichBucket {
  timeBucket: string = '';
  count: number = 0;
}

/** One server album (subset of AlbumResponseDto). */
export class ImmichAlbum {
  id: string = '';
  albumName: string = '';
  description: string = '';
  albumThumbnailAssetId: string = '';
  assetCount: number = 0;
  startDate: string = '';
  endDate: string = '';
}

/** One recognized person (subset of PersonResponseDto). */
export class ImmichPerson {
  id: string = '';
  name: string = '';
}

/** Raw shape of one MapMarkerResponseDto entry. */
export interface ImmichMapMarkerRaw {
  id: string;
  lat: number;
  lon: number;
  city?: string | null;
  state?: string | null;
  country?: string | null;
}

/** One geotagged asset marker for the Places map. */
export class ImmichMapMarker {
  id: string = '';
  lat: number = 0;
  lon: number = 0;
  city: string = '';
  state: string = '';
  country: string = '';
}

/** One memory card ("on this day" etc.) with its assets. */
export class ImmichMemory {
  id: string = '';
  type: string = 'on_this_day';
  /** Display title, e.g. "2 years ago" or the memory year. */
  title: string = '';
  year: number = 0;
  assets: ImmichAsset[] = [];
}

/** Server-visible asset for timeline and viewer. */
export class ImmichAsset {
  id: string = '';
  ratio: number = 1;
  thumbhash: string = '';
  isImage: boolean = true;
  isFavorite: boolean = false;
  isTrashed: boolean = false;
  fileCreatedAt: string = '';
  durationMs: number = 0;
  livePhotoVideoId: string = '';
  visibility: string = 'timeline';

  /** Map one full AssetResponseDto entry into an ImmichAsset. */
  static fromResponseRaw(raw: AssetResponseRaw): ImmichAsset {
    const asset: ImmichAsset = new ImmichAsset();
    asset.id = raw.id;
    asset.thumbhash = raw.thumbhash ?? '';
    asset.isImage = raw.type !== 'VIDEO' && raw.type !== 'AUDIO';
    asset.isFavorite = raw.isFavorite ?? false;
    asset.isTrashed = raw.isTrashed ?? false;
    asset.fileCreatedAt = raw.fileCreatedAt ?? '';
    asset.durationMs = raw.duration ?? 0;
    asset.livePhotoVideoId = raw.livePhotoVideoId ?? '';
    asset.visibility = raw.visibility ?? 'timeline';
    const width: number = raw.width ?? 0;
    const height: number = raw.height ?? 0;
    asset.ratio = width > 0 && height > 0 ? height / width : 1;
    return asset;
  }
}

/** Result of a single asset upload. */
export class ImmichUploadResult {
  id: string = '';
  status: string = 'created';
}

/** Error thrown for non-2xx API responses. */
export class ImmichApiError extends Error {
  readonly statusCode: number;

  constructor(message: string, statusCode: number) {
    super(message);
    this.name = 'ImmichApiError';
    this.statusCode = statusCode;
  }
}
