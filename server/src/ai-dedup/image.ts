import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import sharp from 'sharp';
import type { AiDedupIndexMap } from 'src/ai-dedup/dto.js';

/**
Thumbnail preparation for external vision models.

Privacy rules (PRD §10 / technical design §3.4.3): only a re-encoded JPEG is sent;
rebuilding the JPEG with sharp drops EXIF/XMP/ICC/GPS, and file names, paths, asset ids
and owner ids never enter the buffer. Images are addressed by shuffled 1..N indices only.
*/

/** base64 of a single image must stay below 512 KB; the whole request below 4 MB. */
export const MAX_SINGLE_IMAGE_BASE64_BYTES = 512 * 1024;
export const MAX_TOTAL_BASE64_BYTES = 4 * 1024 * 1024;

export interface AiDedupImageConfig {
  maxImagesPerGroup: number;
  maxImageDimension: number;
  imageQuality: number;
}

export interface AiDedupImagePath {
  assetId: string;
  path: string;
  type: string;
  updateId: string | null;
}

export interface PreparedImage {
  index: number;
  assetId: string;
  base64Jpeg: string;
}

export interface PreparedImageBatch {
  images: PreparedImage[];
  /** Shuffled 1..N index -> assetId. Stored with the result, never sent to the model. */
  indexMap: AiDedupIndexMap;
  /** Members that were not sent (over limit / unreadable / no preview file). */
  unscoredAssetIds: string[];
  truncated: boolean;
}

const typePreference = (type: string): number => {
  if (type === 'preview') {
    return 2;
  }
  return type === 'thumbnail' ? 1 : 0;
};

/** Prefer the preview file (1440px JPEG); fall back to the thumbnail (250px WebP). */
export function selectImagePaths(paths: AiDedupImagePath[]): Map<string, AiDedupImagePath> {
  const selected = new Map<string, AiDedupImagePath>();
  for (const item of paths) {
    const current = selected.get(item.assetId);
    if (!current || typePreference(item.type) > typePreference(current.type)) {
      selected.set(item.assetId, item);
    }
  }
  return selected;
}

/**
Deterministic Fisher-Yates shuffle. Seed = sha256(cacheKey) so the same group and config
always produce the same numbering, while the model never sees the library order.
*/
export function shuffleWithSeed(
  seed: string,
  assetIds: string[],
): { orderedAssetIds: string[]; indexMap: AiDedupIndexMap } {
  const digest = createHash('sha256').update(seed).digest();
  let state = (BigInt(digest.readUInt32LE(0)) << 32n) | BigInt(digest.readUInt32LE(4));
  const next = (): number => {
    state = (state * 6_364_136_223_846_793_005n + 1_442_695_040_888_963_407n) & 0xff_ff_ff_ff_ff_ff_ff_ffn;
    return Number(state >> 11n) / 2 ** 53;
  };

  const orderedAssetIds = [...assetIds].sort();
  for (let i = orderedAssetIds.length - 1; i > 0; i--) {
    const j = Math.floor(next() * (i + 1));
    const left = orderedAssetIds[i];
    orderedAssetIds[i] = orderedAssetIds[j];
    orderedAssetIds[j] = left;
  }

  const indexMap: AiDedupIndexMap = {};
  for (const [position, assetId] of orderedAssetIds.entries()) {
    indexMap[String(position + 1)] = assetId;
  }
  return { orderedAssetIds, indexMap };
}

/** Read and rebuild a JPEG: rotation normalisation + resize + metadata-free re-encode. */
export async function readAndCompress(path: string, config: AiDedupImageConfig): Promise<Buffer> {
  const input = await readFile(path);
  // [ai-dedup] No `unlimited: true`: keep sharp's default pixel cap as a memory guard
  // against corrupt/hostile preview files (readFile already loads the whole file).
  return sharp(input)
    .rotate()
    .resize(config.maxImageDimension, config.maxImageDimension, { fit: 'inside', withoutEnlargement: true })
    .jpeg({ quality: config.imageQuality, mozjpeg: true })
    .toBuffer();
}

/**
Prepare all images for one group. Bad images are skipped (never crash the group), and
members beyond the cap are returned as `unscoredAssetIds` so they are not silently dropped.
*/
export async function prepareImages(
  paths: AiDedupImagePath[],
  config: AiDedupImageConfig,
  seed = 'ai-dedup',
): Promise<PreparedImageBatch> {
  const selected = selectImagePaths(paths);
  const allAssetIds = selected.keys().toArray();
  const { orderedAssetIds } = shuffleWithSeed(seed, allAssetIds);
  const limit = Math.max(1, config.maxImagesPerGroup);
  const candidates = orderedAssetIds.slice(0, limit);

  const images: PreparedImage[] = [];
  const indexMap: AiDedupIndexMap = {};
  let totalBase64Bytes = 0;
  let truncated = orderedAssetIds.length > candidates.length;

  for (const assetId of candidates) {
    const file = selected.get(assetId);
    if (!file) {
      truncated = true;
      continue;
    }

    let base64Jpeg: string;
    try {
      const buffer = await readAndCompress(file.path, config);
      base64Jpeg = buffer.toString('base64');
    } catch {
      truncated = true;
      continue;
    }

    const size = Buffer.byteLength(base64Jpeg, 'utf8');
    if (size > MAX_SINGLE_IMAGE_BASE64_BYTES) {
      truncated = true;
      continue;
    }
    if (totalBase64Bytes + size > MAX_TOTAL_BASE64_BYTES) {
      truncated = true;
      break;
    }

    totalBase64Bytes += size;
    const index = images.length + 1;
    images.push({ index, assetId, base64Jpeg });
    indexMap[String(index)] = assetId;
  }

  const scored = new Set(images.map((image) => image.assetId));
  return {
    images,
    indexMap,
    unscoredAssetIds: allAssetIds.filter((assetId) => !scored.has(assetId)),
    truncated,
  };
}
