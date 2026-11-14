import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import sharp from 'sharp';
import { describe, expect, it } from 'vitest';
import {
  MAX_SINGLE_IMAGE_BASE64_BYTES,
  prepareImages,
  readAndCompress,
  selectImagePaths,
  shuffleWithSeed,
  type AiDedupImageConfig,
  type AiDedupImagePath,
} from 'src/ai-dedup/image.js';

const config: AiDedupImageConfig = {
  maxImagesPerGroup: 8,
  maxImageDimension: 32,
  imageQuality: 70,
};

const path = (assetId: string, type: string, filePath: string): AiDedupImagePath => ({
  assetId,
  path: filePath,
  type,
  updateId: 'file-update-1',
});

const makeJpeg = async (): Promise<Buffer> =>
  sharp({
    create: { width: 64, height: 48, channels: 3, background: { r: 128, g: 128, b: 128 } },
  })
    .jpeg({ quality: 90 })
    .toBuffer();

/** Insert an EXIF APP1 segment carrying a recognizable marker right after the JFIF APP0 segment. */
const withExifMarker = (jpeg: Buffer, marker: string): Buffer => {
  const data = Buffer.from(marker, 'utf8');
  const tiff = Buffer.alloc(26 + data.length, 0);
  tiff.write('II', 0, 'ascii');
  tiff.writeUInt16LE(42, 2);
  tiff.writeUInt32LE(8, 4);
  tiff.writeUInt16LE(1, 8); // one IFD0 entry
  tiff.writeUInt16LE(0x01_0e, 10); // ImageDescription
  tiff.writeUInt16LE(2, 12); // ASCII
  tiff.writeUInt32LE(data.length, 14);
  tiff.writeUInt32LE(26, 18); // value offset
  tiff.writeUInt32LE(0, 22); // no next IFD
  data.copy(tiff, 26);

  const payload = Buffer.concat([Buffer.from('Exif\0\0', 'ascii'), tiff]);
  const segment = Buffer.alloc(4 + payload.length, 0);
  segment[0] = 0xff;
  segment[1] = 0xe1;
  segment.writeUInt16BE(payload.length + 2, 2);
  payload.copy(segment, 4);

  const insertionPoint = 4 + jpeg.readUInt16BE(4); // SOI + JFIF APP0 segment
  return Buffer.concat([jpeg.subarray(0, insertionPoint), segment, jpeg.subarray(insertionPoint)]);
};

describe('selectImagePaths', () => {
  it('prefers the preview file over the thumbnail, one path per asset', () => {
    const paths = [
      path('a', 'thumbnail', '/a-thumb.webp'),
      path('a', 'preview', '/a-preview.jpg'),
      path('b', 'thumbnail', '/b-thumb.webp'),
    ];
    const selected = selectImagePaths(paths);
    expect(selected.keys().toArray()).toEqual(['a', 'b']);
    expect(selected.get('a')?.path).toBe('/a-preview.jpg');
    expect(selected.get('b')?.path).toBe('/b-thumb.webp');
  });
});

describe('shuffleWithSeed', () => {
  const ids = ['a', 'b', 'c', 'd', 'e', 'f'];

  it('is deterministic and a bijection over the members', () => {
    const first = shuffleWithSeed('cache-key-seed', ids);
    const second = shuffleWithSeed('cache-key-seed', ids);
    expect(first.orderedAssetIds).toEqual(second.orderedAssetIds);
    expect([...first.orderedAssetIds].sort()).toEqual([...ids].sort());
    expect(first.indexMap).toEqual(second.indexMap);
  });

  it('assigns stringified 1..N indices (JSON-safe) and different seeds shuffle differently', () => {
    const first = shuffleWithSeed('seed-1', ids);
    const second = shuffleWithSeed('seed-2', ids);
    expect(Object.keys(first.indexMap)).toEqual(['1', '2', '3', '4', '5', '6']);
    expect(first.indexMap['1']).toBe(first.orderedAssetIds[0]);
    expect(first.orderedAssetIds).not.toEqual(second.orderedAssetIds);
  });
});

describe('readAndCompress / prepareImages (privacy)', () => {
  it('rebuilds a metadata-free JPEG and never leaks the source path', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'ai-dedup-image-'));
    const marker = 'SECRET-GPS-COORDINATE-DO-NOT-SEND';
    try {
      const source = withExifMarker(await makeJpeg(), marker);
      const filePath = join(directory, 'private-vacation.jpg');
      await writeFile(filePath, source);
      expect(source.includes(Buffer.from(marker, 'utf8'))).toBe(true);

      const output = await readAndCompress(filePath, config);
      expect(output.subarray(0, 2)).toEqual(Buffer.from([0xff, 0xd8]));
      expect(output.includes(Buffer.from(marker, 'utf8'))).toBe(false);
      expect(output.includes(Buffer.from(filePath, 'utf8'))).toBe(false);

      const metadata = await sharp(output).metadata();
      expect(metadata.format).toBe('jpeg');
      expect(metadata.width).toBeLessThanOrEqual(32);
      expect(metadata.height).toBeLessThanOrEqual(32);
      expect(metadata.exif).toBeUndefined();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  it('returns numbered images, an indexMap and reports truncated members', async () => {
    const directory = await mkdtemp(join(tmpdir(), 'ai-dedup-batch-'));
    try {
      const jpeg = await makeJpeg();
      const files: AiDedupImagePath[] = [];
      for (const id of ['a', 'b', 'c']) {
        const filePath = join(directory, `${id}.jpg`);
        await writeFile(filePath, jpeg);
        files.push(path(id, 'preview', filePath));
      }

      const batch = await prepareImages(files, { ...config, maxImagesPerGroup: 2 }, 'seed');
      expect(batch.images).toHaveLength(2);
      expect(batch.truncated).toBe(true);
      expect(batch.unscoredAssetIds).toHaveLength(1);
      expect(Object.keys(batch.indexMap)).toEqual(['1', '2']);
      expect(batch.images.map((image) => image.index)).toEqual([1, 2]);
      for (const image of batch.images) {
        expect(Buffer.byteLength(image.base64Jpeg, 'utf8')).toBeLessThan(MAX_SINGLE_IMAGE_BASE64_BYTES);
      }
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });

  it('skips unreadable files instead of failing the group', async () => {
    const batch = await prepareImages([path('missing', 'preview', '/definitely/not/here.jpg')], config, 'seed');
    expect(batch.images).toEqual([]);
    expect(batch.truncated).toBe(true);
    expect(batch.unscoredAssetIds).toEqual(['missing']);
  });
});
