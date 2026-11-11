import { preferences } from '@kit.ArkData';
import { util } from '@kit.ArkTS';

/** One persisted backup folder (persisted-permission user folder). */
export class BackupFolderRecord {
  uri: string = '';
  name: string = '';
}

/**
 * Application settings backed by Preferences.
 * Call initSync()/init() once at ability startup; afterwards all accessors are sync.
 */
export class ImmichSettings {
  private static prefs: preferences.Preferences | null = null;

  /** Synchronous initialization so language can be applied before first frame. */
  static initSync(context: Context): void {
    if (ImmichSettings.prefs !== null) {
      return;
    }
    ImmichSettings.prefs = preferences.getPreferencesSync(context, { name: 'immich_settings' });
    if (ImmichSettings.getDeviceId().length === 0) {
      ImmichSettings.prefs.putSync('deviceId', util.generateRandomUUID());
      ImmichSettings.prefs.flush();
    }
  }

  static async init(context: Context): Promise<void> {
    ImmichSettings.initSync(context);
  }

  /** App language tag ('zh-Hans' | 'en-Latn-US'); defaults to Chinese. */
  static getAppLanguage(): string {
    return ImmichSettings.getString('appLanguage', 'zh-Hans');
  }

  static setAppLanguage(language: string): void {
    ImmichSettings.putString('appLanguage', language);
  }

  static getDeviceId(): string {
    return ImmichSettings.getString('deviceId', '');
  }

  static getServerUrl(): string {
    return ImmichSettings.getString('serverUrl', '');
  }

  static setServerUrl(url: string): void {
    ImmichSettings.putString('serverUrl', url);
  }

  static getUserName(): string {
    return ImmichSettings.getString('userName', '');
  }

  static setUserName(name: string): void {
    ImmichSettings.putString('userName', name);
  }

  static getUserEmail(): string {
    return ImmichSettings.getString('userEmail', '');
  }

  static setUserEmail(email: string): void {
    ImmichSettings.putString('userEmail', email);
  }

  static getBackupEnabled(): boolean {
    return ImmichSettings.getBoolean('backupEnabled', false);
  }

  static setBackupEnabled(enabled: boolean): void {
    const prefs: preferences.Preferences | null = ImmichSettings.prefs;
    if (prefs === null) {
      return;
    }
    prefs.putSync('backupEnabled', enabled);
    prefs.flush();
  }

  static getBackupFolders(): BackupFolderRecord[] {
    const raw: string = ImmichSettings.getString('backupFolders', '[]');
    try {
      const parsed: BackupFolderRecord[] = JSON.parse(raw) as BackupFolderRecord[];
      return parsed;
    } catch (err) {
      return [];
    }
  }

  static setBackupFolders(folders: BackupFolderRecord[]): void {
    ImmichSettings.putString('backupFolders', JSON.stringify(folders));
  }

  /** Fallback (non-asset-store) token storage key, internal use only. */
  static getFallbackToken(): string {
    return ImmichSettings.getString('fallbackToken', '');
  }

  static setFallbackToken(token: string): void {
    ImmichSettings.putString('fallbackToken', token);
  }

  static clearFallbackToken(): void {
    const prefs: preferences.Preferences | null = ImmichSettings.prefs;
    if (prefs === null) {
      return;
    }
    prefs.deleteSync('fallbackToken');
    prefs.flush();
  }

  private static getString(key: string, def: string): string {
    const raw: preferences.ValueType =
      ImmichSettings.prefs?.getSync(key, def) ?? def;
    return typeof raw === 'string' ? raw : def;
  }

  private static putString(key: string, value: string): void {
    const prefs: preferences.Preferences | null = ImmichSettings.prefs;
    if (prefs === null) {
      return;
    }
    prefs.putSync(key, value);
    prefs.flush();
  }

  private static getBoolean(key: string, def: boolean): boolean {
    const raw: preferences.ValueType =
      ImmichSettings.prefs?.getSync(key, def) ?? def;
    return typeof raw === 'boolean' ? raw : def;
  }
}
