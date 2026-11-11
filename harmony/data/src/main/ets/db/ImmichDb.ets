import { relationalStore } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';

/** Upload state of a local asset. */
export enum UploadState {
  PENDING = 0,
  UPLOADING = 1,
  DONE = 2,
  FAILED = 3
}

/** A local file tracked for backup. */
export class LocalAssetRecord {
  uri: string = '';
  path: string = '';
  name: string = '';
  folderUri: string = '';
  size: number = 0;
  mtimeMs: number = 0;
  state: number = UploadState.PENDING;
}

/**
 * Local RDB database tracking which device files have been backed up.
 */
export class ImmichDb {
  private store: relationalStore.RdbStore | null = null;

  static async create(context: Context): Promise<ImmichDb> {
    const config: relationalStore.StoreConfig = {
      name: 'immich.db',
      securityLevel: relationalStore.SecurityLevel.S1,
      encrypt: true
    };
    const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    const db: ImmichDb = new ImmichDb();
    db.store = store;
    await store.executeSql(`CREATE TABLE IF NOT EXISTS local_asset (
      uri TEXT PRIMARY KEY,
      path TEXT NOT NULL,
      name TEXT NOT NULL,
      folder_uri TEXT NOT NULL,
      size INTEGER NOT NULL,
      mtime_ms INTEGER NOT NULL,
      state INTEGER NOT NULL DEFAULT 0,
      uploaded_at INTEGER
    )`);
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_local_asset_state ON local_asset(state)');
    await store.executeSql('CREATE INDEX IF NOT EXISTS idx_local_asset_folder ON local_asset(folder_uri)');
    return db;
  }

  /**
   * Batch upsert of scanned files. Existing rows keep their upload state;
   * a changed mtime resets the state to PENDING so the file re-uploads.
   */
  async upsertAssets(records: LocalAssetRecord[]): Promise<void> {
    if (records.length === 0 || this.store === null) {
      return;
    }
    const store: relationalStore.RdbStore = this.store;
    store.beginTransaction();
    try {
      for (const rec of records) {
        const args: Array<relationalStore.ValueType> =
          [rec.uri, rec.path, rec.name, rec.folderUri, rec.size, rec.mtimeMs];
        await store.executeSql(`INSERT INTO local_asset (uri, path, name, folder_uri, size, mtime_ms, state)
          VALUES (?, ?, ?, ?, ?, ?, 0)
          ON CONFLICT(uri) DO UPDATE SET
            path=excluded.path,
            size=excluded.size,
            mtime_ms=excluded.mtime_ms,
            state=CASE WHEN local_asset.mtime_ms <> excluded.mtime_ms THEN 0 ELSE local_asset.state END`,
          args);
      }
      store.commit();
    } catch (err) {
      store.rollBack();
      const error: BusinessError = err as BusinessError;
      throw new Error(`upsert assets failed: ${error.message}`);
    }
  }

  /** Remove DB rows for files that no longer exist in a folder. */
  async removeMissing(folderUri: string, existingUris: Set<string>): Promise<void> {
    if (this.store === null) {
      return;
    }
    const all: LocalAssetRecord[] = await this.getAssetsInFolder(folderUri);
    const removed: string[] = [];
    for (const rec of all) {
      if (!existingUris.has(rec.uri)) {
        removed.push(rec.uri);
      }
    }
    for (const uri of removed) {
      await this.store.executeSql('DELETE FROM local_asset WHERE uri = ?', [uri]);
    }
  }

  async getAssetsInFolder(folderUri: string): Promise<LocalAssetRecord[]> {
    if (this.store === null) {
      return [];
    }
    const resultSet: relationalStore.ResultSet =
      await this.store.querySql('SELECT uri, path, name, folder_uri, size, mtime_ms, state FROM local_asset WHERE folder_uri = ?',
        [folderUri]);
    return ImmichDb.readAll(resultSet);
  }

  /** Assets awaiting upload (pending or failed) in the given folders. */
  async getPendingAssets(folderUris: string[]): Promise<LocalAssetRecord[]> {
    if (this.store === null || folderUris.length === 0) {
      return [];
    }
    const placeholders: string[] = [];
    const args: Array<relationalStore.ValueType> = [];
    for (const uri of folderUris) {
      placeholders.push('?');
      args.push(uri);
    }
    const sql: string = `SELECT uri, path, name, folder_uri, size, mtime_ms, state FROM local_asset
      WHERE state IN (0, 3) AND folder_uri IN (${placeholders.join(',')}) ORDER BY mtime_ms ASC`;
    const resultSet: relationalStore.ResultSet = await this.store.querySql(sql, args);
    return ImmichDb.readAll(resultSet);
  }

  async setState(uri: string, state: number): Promise<void> {
    if (this.store === null) {
      return;
    }
    const uploadedAt: number = state === UploadState.DONE ? Date.now() : -1;
    await this.store.executeSql('UPDATE local_asset SET state = ?, uploaded_at = ? WHERE uri = ?',
      [state, uploadedAt, uri]);
  }

  async countByState(state: number): Promise<number> {
    if (this.store === null) {
      return 0;
    }
    const resultSet: relationalStore.ResultSet =
      await this.store.querySql('SELECT COUNT(*) AS cnt FROM local_asset WHERE state = ?', [state]);
    let count: number = 0;
    try {
      if (resultSet.goToNextRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count;
  }

  async totalAssets(): Promise<number> {
    if (this.store === null) {
      return 0;
    }
    const resultSet: relationalStore.ResultSet =
      await this.store.querySql('SELECT COUNT(*) AS cnt FROM local_asset');
    let count: number = 0;
    try {
      if (resultSet.goToNextRow()) {
        count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      }
    } finally {
      resultSet.close();
    }
    return count;
  }

  private static readAll(resultSet: relationalStore.ResultSet): LocalAssetRecord[] {
    const records: LocalAssetRecord[] = [];
    try {
      while (resultSet.goToNextRow()) {
        const rec: LocalAssetRecord = new LocalAssetRecord();
        rec.uri = resultSet.getString(resultSet.getColumnIndex('uri'));
        rec.path = resultSet.getString(resultSet.getColumnIndex('path'));
        rec.name = resultSet.getString(resultSet.getColumnIndex('name'));
        rec.folderUri = resultSet.getString(resultSet.getColumnIndex('folder_uri'));
        rec.size = resultSet.getLong(resultSet.getColumnIndex('size'));
        rec.mtimeMs = resultSet.getLong(resultSet.getColumnIndex('mtime_ms'));
        rec.state = resultSet.getLong(resultSet.getColumnIndex('state'));
        records.push(rec);
      }
    } finally {
      resultSet.close();
    }
    return records;
  }
}
