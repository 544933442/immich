import { common } from '@kit.AbilityKit';
import { ImmichDb, ImmichSettings, CredentialStore } from 'data';
import { ImmichApiConfig, authState } from 'network';
import { BackupEngine, BackupScheduler, ImmichBackgroundTask, ImmichBackupNotifier } from 'backup';
import { AssetImageLoader } from '../view/timeline/AssetImageLoader';

/**
 * Process-wide runtime singletons: settings, database, backup engine and
 * the UIAbility context. Initialized once at startup.
 */
export class AppRuntime {
  private static context: Context | null = null;
  private static abilityContext: common.UIAbilityContext | null = null;
  private static db: ImmichDb | null = null;
  private static engine: BackupEngine | null = null;
  private static initPromise: Promise<void> | null = null;

  static init(context: Context): Promise<void> {
    if (AppRuntime.initPromise === null) {
      AppRuntime.initPromise = AppRuntime.doInit(context);
    }
    return AppRuntime.initPromise;
  }

  /** Provide the UIAbility context (for notification permission dialogs). */
  static setAbilityContext(context: common.UIAbilityContext): void {
    AppRuntime.abilityContext = context;
  }

  /** Await startup initialization started by the EntryAbility. */
  static whenReady(): Promise<void> {
    if (AppRuntime.initPromise === null) {
      return Promise.reject(new Error('runtime not initialized'));
    }
    return AppRuntime.initPromise;
  }

  private static async doInit(context: Context): Promise<void> {
    AppRuntime.context = context;
    await ImmichSettings.init(context);
    AppRuntime.db = await ImmichDb.create(context);
    AppRuntime.engine = new BackupEngine(context, AppRuntime.db);
    await AssetImageLoader.init(context);
    const server: string = ImmichSettings.getServerUrl();
    const token: string = await CredentialStore.getToken();
    authState.serverUrl = server;
    if (server.length > 0 && token.length > 0) {
      ImmichApiConfig.setServer(server);
      ImmichApiConfig.setToken(token);
      authState.userName = ImmichSettings.getUserName();
      authState.userEmail = ImmichSettings.getUserEmail();
      authState.loggedIn = true;
    }
  }

  static getContext(): Context {
    if (AppRuntime.context === null) {
      throw new Error('AppRuntime not initialized');
    }
    return AppRuntime.context;
  }

  static getEngine(): BackupEngine {
    if (AppRuntime.engine === null) {
      throw new Error('AppRuntime not initialized');
    }
    return AppRuntime.engine;
  }

  /**
   * Run a full backup session wrapped in a continuous "dataTransfer"
   * background task so it can continue while the app is in background.
   */
  static async runBackup(): Promise<void> {
    const engine: BackupEngine = AppRuntime.getEngine();
    const context: Context = AppRuntime.getContext();
    const abilityContext: common.UIAbilityContext | null = AppRuntime.abilityContext;
    if (abilityContext !== null) {
      await ImmichBackupNotifier.requestPermission(abilityContext);
    }
    try {
      await ImmichBackgroundTask.start(context, 'app.yyzh999.immich', 'EntryAbility');
    } catch (err) {
      // background task is an optimization; continue in foreground
    }
    try {
      await engine.syncAndUpload();
    } finally {
      ImmichBackupNotifier.cancel();
      try {
        await ImmichBackgroundTask.stop(context);
      } catch (err) {
        // ignore stop failure
      }
    }
  }

  static async logout(): Promise<void> {
    BackupScheduler.disable();
    await CredentialStore.clearToken();
    ImmichApiConfig.setToken('');
    authState.loggedIn = false;
  }
}
