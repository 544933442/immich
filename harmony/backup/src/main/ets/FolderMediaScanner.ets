import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { LocalAssetRecord, UploadState } from 'data';

const IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif',
  '.dng', '.tif', '.tiff', '.avif', '.bmp'];
const VIDEO_EXTENSIONS: string[] = ['.mp4', '.mov', '.webm', '.mkv', '.avi', '.m4v', '.3gp'];

/**
 * Recursively scans a persisted user folder for backup-eligible media files.
 */
export class FolderMediaScanner {
  /**
   * Scan one folder; returns records for every supported media file found.
   * Files are keyed by their user-file URI so re-scans stay stable.
   */
  static scanFolder(folderUri: string, folderName: string): LocalAssetRecord[] {
    const records: LocalAssetRecord[] = [];
    let rootPath: string = '';
    try {
      rootPath = new fileUri.FileUri(folderUri).path;
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      throw new Error(`invalid folder uri ${folderUri}: ${error.message}`);
    }
    FolderMediaScanner.walk(folderUri, folderName, rootPath, records);
    return records;
  }

  static contentTypeOf(name: string): string {
    const lower: string = name.toLowerCase();
    if (FolderMediaScanner.hasAny(lower, IMAGE_EXTENSIONS)) {
      if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
        return 'image/jpeg';
      }
      if (lower.endsWith('.png')) {
        return 'image/png';
      }
      if (lower.endsWith('.gif')) {
        return 'image/gif';
      }
      if (lower.endsWith('.webp')) {
        return 'image/webp';
      }
      if (lower.endsWith('.heic') || lower.endsWith('.heif')) {
        return 'image/heic';
      }
      if (lower.endsWith('.avif')) {
        return 'image/avif';
      }
      if (lower.endsWith('.bmp')) {
        return 'image/bmp';
      }
      return 'image/tiff';
    }
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) {
      return 'video/mp4';
    }
    if (lower.endsWith('.mov')) {
      return 'video/quicktime';
    }
    if (lower.endsWith('.webm')) {
      return 'video/webm';
    }
    return 'video/mp2t';
  }

  static isMediaFile(name: string): boolean {
    const lower: string = name.toLowerCase();
    return FolderMediaScanner.hasAny(lower, IMAGE_EXTENSIONS) ||
      FolderMediaScanner.hasAny(lower, VIDEO_EXTENSIONS);
  }

  private static hasAny(lowerName: string, extensions: string[]): boolean {
    for (const ext of extensions) {
      if (lowerName.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  private static walk(folderUri: string, folderName: string, dirPath: string,
    out: LocalAssetRecord[]): void {
    let names: string[] = [];
    try {
      names = fs.listFileSync(dirPath);
    } catch (err) {
      return;
    }
    for (const name of names) {
      const childPath: string = `${dirPath}/${name}`;
      let isDir: boolean = false;
      try {
        const stat: fs.Stat = fs.statSync(childPath);
        isDir = stat.isDirectory();
        if (!isDir && FolderMediaScanner.isMediaFile(name)) {
          const rec: LocalAssetRecord = new LocalAssetRecord();
          rec.uri = FolderMediaScanner.fileUriOf(childPath);
          rec.path = childPath;
          rec.name = name;
          rec.folderUri = folderUri;
          rec.size = stat.size;
          rec.mtimeMs = stat.mtime * 1000;
          rec.state = UploadState.PENDING;
          out.push(rec);
        }
      } catch (err) {
        continue;
      }
      if (isDir) {
        FolderMediaScanner.walk(folderUri, folderName, childPath, out);
      }
    }
  }

  private static fileUriOf(path: string): string {
    return `file://${path}`;
  }
}
