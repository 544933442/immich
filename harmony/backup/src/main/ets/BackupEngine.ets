import { AsyncMutex } from 'commons';
import {
  ImmichAssetApi,
  ImmichUploadResult,
  UploadAssetRequest,
  ImmichApiError
} from 'network';
import { ImmichDb, ImmichSettings, LocalAssetRecord, UploadState } from 'data';
import { FolderMediaScanner } from './FolderMediaScanner';
import { ImmichBackupNotifier } from './ImmichBackupNotifier';
import { backupState } from './state/BackupStateHolder';

/**
 * Drives one backup session: scan configured folders, sync the local DB,
 * then upload pending assets with a small worker pool, reporting progress
 * through the shared BackupStateHolder and system notifications.
 */
export class BackupEngine {
  private static readonly UPLOAD_CONCURRENCY = 2;
  private static readonly MAX_ATTEMPTS = 3;
  private static readonly RETRY_BASE_DELAY_MS = 2000;

  private db: ImmichDb;
  private mutex: AsyncMutex = new AsyncMutex();

  constructor(db: ImmichDb) {
    this.db = db;
  }

  /** Rescan all configured folders and refresh the pending count. */
  async refreshPending(): Promise<number> {
    return this.mutex.run(async (): Promise<number> => {
      await this.scanFolders();
      const folders = ImmichSettings.getBackupFolders();
      const uris: string[] = [];
      for (const folder of folders) {
        uris.push(folder.uri);
      }
      const pending: LocalAssetRecord[] = await this.db.getPendingAssets(uris);
      backupState.pendingCount = pending.length;
      return pending.length;
    });
  }

  /** Full session: scan folders, then upload all pending assets. */
  async syncAndUpload(): Promise<void> {
    await this.mutex.run(async (): Promise<void> => {
      if (backupState.running) {
        return;
      }
      backupState.running = true;
      backupState.lastError = '';
      try {
        backupState.phase = 'scanning';
        await this.scanFolders();
        const folders = ImmichSettings.getBackupFolders();
        const uris: string[] = [];
        for (const folder of folders) {
          uris.push(folder.uri);
        }
        const pending: LocalAssetRecord[] = await this.db.getPendingAssets(uris);
        backupState.totalCount = pending.length;
        backupState.doneCount = 0;
        backupState.failedCount = 0;
        backupState.pendingCount = pending.length;
        backupState.phase = 'uploading';
        ImmichBackupNotifier.publishScanProgress();
        await this.uploadAll(pending);
        ImmichBackupNotifier.publishDone(backupState.doneCount, backupState.totalCount,
          backupState.failedCount);
        backupState.phase = 'idle';
      } catch (err) {
        backupState.phase = 'idle';
        const message: string = err instanceof Error ? err.message : 'backup failed';
        backupState.lastError = message;
        throw new Error(message);
      } finally {
        backupState.running = false;
        backupState.currentFile = '';
        backupState.progressSent = 0;
        backupState.progressTotal = 0;
        await this.refreshPendingCountOnly();
      }
    });
  }

  /** Request graceful stop of the current session after the current file. */
  cancel(): void {
    backupState.running = false;
  }

  private async uploadAll(pending: LocalAssetRecord[]): Promise<void> {
    let cursor: number = 0;
    const nextIndex = (): number => {
      if (cursor < pending.length) {
        const index: number = cursor;
        cursor += 1;
        return index;
      }
      return pending.length;
    };
    const workers: Promise<void>[] = [];
    const workerCount: number = Math.min(BackupEngine.UPLOAD_CONCURRENCY, pending.length);
    for (let w = 0; w < workerCount; w++) {
      workers.push(this.uploadWorker(pending, nextIndex));
    }
    await Promise.all(workers);
  }

  private async uploadWorker(pending: LocalAssetRecord[], nextIndex: () => number): Promise<void> {
    while (backupState.running) {
      const i: number = nextIndex();
      if (i >= pending.length) {
        return;
      }
      const rec: LocalAssetRecord = pending[i];
      try {
        await this.uploadWithRetry(rec);
        backupState.doneCount += 1;
      } catch (err) {
        if (!backupState.running) {
          return;
        }
        await this.db.setState(rec.uri, UploadState.FAILED);
        backupState.failedCount += 1;
        const message: string = err instanceof Error ? err.message : 'upload failed';
        backupState.lastError = `${rec.name}: ${message}`;
      }
      ImmichBackupNotifier.publishUploadProgress(backupState.doneCount, backupState.totalCount,
        backupState.failedCount);
    }
  }

  private async uploadWithRetry(rec: LocalAssetRecord): Promise<void> {
    let attempt: number = 0;
    let delayMs: number = BackupEngine.RETRY_BASE_DELAY_MS;
    let lastError: Error = new Error('upload failed');
    while (attempt < BackupEngine.MAX_ATTEMPTS) {
      if (!backupState.running) {
        throw new Error('backup cancelled');
      }
      try {
        await this.uploadOnce(rec);
        return;
      } catch (err) {
        if (err instanceof ImmichApiError && err.statusCode >= 400 && err.statusCode < 500 &&
          err.statusCode !== 429) {
          throw err;
        }
        lastError = err instanceof Error ? err : new Error('upload failed');
        attempt += 1;
        if (attempt < BackupEngine.MAX_ATTEMPTS) {
          await BackupEngine.sleep(delayMs);
          delayMs *= 4;
        }
      }
    }
    throw lastError;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }

  private async uploadOnce(rec: LocalAssetRecord): Promise<void> {
    backupState.currentFile = rec.name;
    backupState.progressSent = 0;
    backupState.progressTotal = rec.size;
    await this.db.setState(rec.uri, UploadState.UPLOADING);
    try {
      const request: UploadAssetRequest = BackupEngine.buildRequest(rec);
      const result: ImmichUploadResult = await ImmichAssetApi.uploadAsset(request,
        (sent: number, total: number): void => {
          backupState.progressSent = sent;
          backupState.progressTotal = total;
        });
      await this.db.setState(rec.uri, UploadState.DONE);
      if (result.status !== 'created' && result.status !== 'duplicate') {
        backupState.lastError = `unexpected upload status: ${result.status}`;
      }
    } finally {
      backupState.currentFile = '';
      backupState.progressSent = 0;
      backupState.progressTotal = 0;
    }
  }

  private static buildRequest(rec: LocalAssetRecord): UploadAssetRequest {
    const request: UploadAssetRequest = new UploadAssetRequest();
    request.filePath = rec.path;
    request.fileName = rec.name;
    request.contentType = FolderMediaScanner.contentTypeOf(rec.name);
    request.deviceAssetId = `${rec.name}-${rec.size}-${rec.mtimeMs}`;
    request.deviceId = ImmichSettings.getDeviceId();
    const mtime: Date = new Date(rec.mtimeMs);
    const iso: string = mtime.toISOString();
    request.fileCreatedAtIso = iso;
    request.fileModifiedAtIso = iso;
    request.isFavorite = false;
    request.durationMs = 0;
    return request;
  }

  private async scanFolders(): Promise<void> {
    const folders = ImmichSettings.getBackupFolders();
    for (const folder of folders) {
      try {
        const records: LocalAssetRecord[] = FolderMediaScanner.scanFolder(folder.uri, folder.name);
        await this.db.upsertAssets(records);
        const existing: Set<string> = new Set<string>();
        for (const rec of records) {
          existing.add(rec.uri);
        }
        await this.db.removeMissing(folder.uri, existing);
      } catch (err) {
        const message: string = err instanceof Error ? err.message : `${err}`;
        backupState.lastError = `${folder.name}: ${message}`;
      }
    }
  }

  private async refreshPendingCountOnly(): Promise<void> {
    try {
      const folders = ImmichSettings.getBackupFolders();
      const uris: string[] = [];
      for (const folder of folders) {
        uris.push(folder.uri);
      }
      const pending: LocalAssetRecord[] = await this.db.getPendingAssets(uris);
      backupState.pendingCount = pending.length;
    } catch (err) {
      // counting is best-effort
    }
  }
}
