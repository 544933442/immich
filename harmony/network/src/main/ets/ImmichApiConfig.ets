/**
 * Immutable connection configuration shared by all API calls.
 */
export class ImmichApiConfig {
  private static serverUrl: string = '';
  private static accessToken: string = '';

  static setServer(url: string): void {
    let normalized: string = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = `https://${normalized}`;
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.slice(0, normalized.length - 1);
    }
    ImmichApiConfig.serverUrl = normalized;
  }

  static getServer(): string {
    return ImmichApiConfig.serverUrl;
  }

  static setToken(token: string): void {
    ImmichApiConfig.accessToken = token;
  }

  static getToken(): string {
    return ImmichApiConfig.accessToken;
  }

  static url(path: string): string {
    // All Immich API routes live under /api (see open-api servers entry).
    return `${ImmichApiConfig.serverUrl}/api${path}`;
  }

  static authHeaders(extra?: Record<string, string>): Record<string, string> {
    const headers: Record<string, string> = {};
    if (ImmichApiConfig.accessToken.length > 0) {
      headers['Authorization'] = `Bearer ${ImmichApiConfig.accessToken}`;
    }
    if (extra !== undefined) {
      const keys: string[] = Object.keys(extra);
      for (const key of keys) {
        headers[key] = extra[key];
      }
    }
    return headers;
  }
}
