import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { ImmichSettings } from './ImmichSettings';

const TOKEN_ALIAS: string = 'immich_access_token';

/**
 * Secure credential storage. Primary backend is the Asset Store Kit
 * (HUKS-backed key-value store); Preferences is a last-resort fallback so
 * login still works on environments where the asset service is unavailable.
 */
export class CredentialStore {
  private static encoder(): util.TextEncoder {
    return new util.TextEncoder();
  }

  static async saveToken(token: string): Promise<void> {
    try {
      const removeQuery: asset.AssetMap = new Map();
      removeQuery.set(asset.Tag.ALIAS, CredentialStore.encoder().encode(TOKEN_ALIAS));
      try {
        await asset.remove(removeQuery);
      } catch (err) {
        // absence is expected on first login
      }
      const attrs: asset.AssetMap = new Map();
      attrs.set(asset.Tag.ALIAS, CredentialStore.encoder().encode(TOKEN_ALIAS));
      attrs.set(asset.Tag.SECRET, CredentialStore.encoder().encode(token));
      attrs.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      await asset.add(attrs);
      ImmichSettings.clearFallbackToken();
    } catch (err) {
      ImmichSettings.setFallbackToken(token);
    }
  }

  static async getToken(): Promise<string> {
    try {
      const query: asset.AssetMap = new Map();
      query.set(asset.Tag.ALIAS, CredentialStore.encoder().encode(TOKEN_ALIAS));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      const result: Array<asset.AssetMap> = await asset.query(query);
      if (result.length === 0) {
        return ImmichSettings.getFallbackToken();
      }
      const secret = result[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return ImmichSettings.getFallbackToken();
      }
      const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
      return decoder.decodeToString(secret);
    } catch (err) {
      return ImmichSettings.getFallbackToken();
    }
  }

  static async clearToken(): Promise<void> {
    try {
      const removeQuery: asset.AssetMap = new Map();
      removeQuery.set(asset.Tag.ALIAS, CredentialStore.encoder().encode(TOKEN_ALIAS));
      await asset.remove(removeQuery);
    } catch (err) {
      // token may already be gone
    }
    ImmichSettings.clearFallbackToken();
  }
}
