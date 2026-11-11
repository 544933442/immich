import { http } from '@kit.NetworkKit';
import { ImmichHttpClient } from '../ImmichHttpClient';
import { ImmichAlbum, ImmichAlbumRaw } from '../model/ApiModels';

/** Body of POST /albums. */
export interface CreateAlbumRequest {
  albumName: string;
}

/** Body of PATCH /albums/{id}. */
export interface UpdateAlbumRequest {
  albumName: string;
}

/** Body of PUT/DELETE /albums/{id}/assets. */
export interface BulkIdsRequest {
  ids: string[];
}

/** Body of PUT /albums/assets (add assets to several albums at once). */
export interface AlbumsAddAssetsRequest {
  albumIds: string[];
  assetIds: string[];
}

/** Server album APIs. */
export class ImmichAlbumApi {
  /** GET /albums — all albums visible to the current user. */
  static async getAlbums(): Promise<ImmichAlbum[]> {
    const text: string = await ImmichHttpClient.requestJsonText(http.RequestMethod.GET, '/albums');
    const raw: ImmichAlbumRaw[] = JSON.parse(text) as ImmichAlbumRaw[];
    const albums: ImmichAlbum[] = [];
    for (const entry of raw) {
      const album: ImmichAlbum = new ImmichAlbum();
      album.id = entry.id;
      album.albumName = entry.albumName;
      album.description = entry.description ?? '';
      album.albumThumbnailAssetId = entry.albumThumbnailAssetId ?? '';
      album.assetCount = entry.assetCount ?? 0;
      album.startDate = entry.startDate ?? '';
      album.endDate = entry.endDate ?? '';
      albums.push(album);
    }
    return albums;
  }

  /** POST /albums — create an empty album and return its id. */
  static async createAlbum(albumName: string): Promise<ImmichAlbum> {
    const body: CreateAlbumRequest = { albumName: albumName };
    const text: string =
      await ImmichHttpClient.requestJsonText(http.RequestMethod.POST, '/albums', body);
    const raw: ImmichAlbumRaw = JSON.parse(text) as ImmichAlbumRaw;
    const album: ImmichAlbum = new ImmichAlbum();
    album.id = raw.id;
    album.albumName = raw.albumName;
    album.assetCount = raw.assetCount ?? 0;
    return album;
  }

  /** PATCH /albums/{id} — rename an album. */
  static async updateAlbumName(id: string, albumName: string): Promise<void> {
    const body: UpdateAlbumRequest = { albumName: albumName };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.PATCH, `/albums/${id}`, body);
  }

  /** DELETE /albums/{id} — delete an album (assets stay in the library). */
  static async deleteAlbum(id: string): Promise<void> {
    await ImmichHttpClient.requestJsonText(http.RequestMethod.DELETE, `/albums/${id}`);
  }

  /** PUT /albums/{id}/assets — add assets to an album. */
  static async addAssetsToAlbum(id: string, assetIds: string[]): Promise<void> {
    const body: BulkIdsRequest = { ids: assetIds };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.PUT, `/albums/${id}/assets`, body);
  }

  /** DELETE /albums/{id}/assets — remove assets from an album. */
  static async removeAssetsFromAlbum(id: string, assetIds: string[]): Promise<void> {
    const body: BulkIdsRequest = { ids: assetIds };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.DELETE, `/albums/${id}/assets`, body);
  }

  /** PUT /albums/assets — add assets to one or more albums. */
  static async addAssetsToAlbums(albumIds: string[], assetIds: string[]): Promise<void> {
    const body: AlbumsAddAssetsRequest = { albumIds: albumIds, assetIds: assetIds };
    await ImmichHttpClient.requestJsonText(http.RequestMethod.PUT, '/albums/assets', body);
  }
}
