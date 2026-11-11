/**
 * ThumbHash placeholder decoder, ported from the official thumbhash
 * reference implementation (https://github.com/evanw/thumbhash, MIT).
 */
export class ThumbHashImage {
  width: number = 0;
  height: number = 0;
  rgba: Uint8Array = new Uint8Array(0);
}

export class ThumbHash {
  static approximateAspectRatio(hash: Uint8Array): number {
    const header: number = hash[3];
    const hasAlpha: number = hash[2] & 0x80;
    const isLandscape: number = hash[4] & 0x80;
    const lx: number = isLandscape ? (hasAlpha ? 5 : 7) : header & 7;
    const ly: number = isLandscape ? header & 7 : (hasAlpha ? 5 : 7);
    return lx / ly;
  }

  static thumbHashToRGBA(hash: Uint8Array): ThumbHashImage {
    const PI: number = Math.PI;
    const min: (x: number, y: number) => number = Math.min;
    const max: (x: number, y: number) => number = Math.max;
    const cos: (x: number) => number = Math.cos;
    const round: (x: number) => number = Math.round;

    const header24: number = hash[0] | (hash[1] << 8) | (hash[2] << 16);
    const header16: number = hash[3] | (hash[4] << 8);
    const l_dc: number = (header24 & 63) / 63;
    const p_dc: number = ((header24 >> 6) & 63) / 31.5 - 1;
    const q_dc: number = ((header24 >> 12) & 63) / 31.5 - 1;
    const l_scale: number = ((header24 >> 18) & 31) / 31;
    const hasAlpha: number = header24 >> 23;
    const p_scale: number = ((header16 >> 3) & 63) / 63;
    const q_scale: number = ((header16 >> 9) & 63) / 63;
    const isLandscape: number = header16 >> 15;
    const lx: number = max(3, isLandscape ? (hasAlpha ? 5 : 7) : header16 & 7);
    const ly: number = max(3, isLandscape ? header16 & 7 : (hasAlpha ? 5 : 7));
    const a_dc: number = hasAlpha ? (hash[5] & 15) / 15 : 1;
    const a_scale: number = (hash[5] >> 4) / 15;

    const acStart: number = hasAlpha ? 6 : 5;
    const l_ac: number[] = ThumbHash.decodeChannel(hash, acStart, lx, ly, l_scale);
    let acIndex: number = ThumbHash.channelCount(lx, ly);
    const p_ac: number[] = ThumbHash.decodeChannelAt(hash, acStart, acIndex, 3, 3, p_scale * 1.25);
    acIndex += ThumbHash.channelCount(3, 3);
    const q_ac: number[] = ThumbHash.decodeChannelAt(hash, acStart, acIndex, 3, 3, q_scale * 1.25);
    acIndex += ThumbHash.channelCount(3, 3);
    const a_ac: number[] = hasAlpha ?
      ThumbHash.decodeChannelAt(hash, acStart, acIndex, 5, 5, a_scale) : [];

    const ratio: number = ThumbHash.approximateAspectRatio(hash);
    const w: number = round(ratio > 1 ? 32 : 32 * ratio);
    const h: number = round(ratio > 1 ? 32 / ratio : 32);
    const rgba: Uint8Array = new Uint8Array(w * h * 4);
    const fx: number[] = [];
    const fy: number[] = [];
    for (let y = 0, i = 0; y < h; y++) {
      for (let x = 0; x < w; x++, i += 4) {
        let l: number = l_dc;
        let p: number = p_dc;
        let q: number = q_dc;
        let a: number = a_dc;

        for (let cx = 0, n = max(lx, hasAlpha ? 5 : 3); cx < n; cx++) {
          fx[cx] = cos(PI / w * (x + 0.5) * cx);
        }
        for (let cy = 0, n = max(ly, hasAlpha ? 5 : 3); cy < n; cy++) {
          fy[cy] = cos(PI / h * (y + 0.5) * cy);
        }

        for (let cy = 0, j = 0; cy < ly; cy++) {
          const fy2: number = fy[cy] * 2;
          for (let cx = cy ? 0 : 1; cx * ly < lx * (ly - cy); cx++, j++) {
            l += l_ac[j] * fx[cx] * fy2;
          }
        }

        for (let cy = 0, j = 0; cy < 3; cy++) {
          const fy2: number = fy[cy] * 2;
          for (let cx = cy ? 0 : 1; cx < 3 - cy; cx++, j++) {
            const f: number = fx[cx] * fy2;
            p += p_ac[j] * f;
            q += q_ac[j] * f;
          }
        }

        if (hasAlpha) {
          for (let cy = 0, j = 0; cy < 5; cy++) {
            const fy2: number = fy[cy] * 2;
            for (let cx = cy ? 0 : 1; cx < 5 - cy; cx++, j++) {
              a += a_ac[j] * fx[cx] * fy2;
            }
          }
        }

        const b: number = l - 2 / 3 * p;
        const r: number = (3 * l - b + q) / 2;
        const g: number = r - q;
        rgba[i] = max(0, 255 * min(1, r));
        rgba[i + 1] = max(0, 255 * min(1, g));
        rgba[i + 2] = max(0, 255 * min(1, b));
        rgba[i + 3] = max(0, 255 * min(1, a));
      }
    }
    const image: ThumbHashImage = new ThumbHashImage();
    image.width = w;
    image.height = h;
    image.rgba = rgba;
    return image;
  }

  private static channelCount(nx: number, ny: number): number {
    let count: number = 0;
    for (let cy = 0; cy < ny; cy++) {
      for (let cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        count++;
      }
    }
    return count;
  }

  private static decodeChannel(hash: Uint8Array, acStart: number, nx: number, ny: number, scale: number): number[] {
    return ThumbHash.decodeChannelAt(hash, acStart, 0, nx, ny, scale);
  }

  private static decodeChannelAt(hash: Uint8Array, acStart: number, acOffset: number, nx: number, ny: number,
    scale: number): number[] {
    const ac: number[] = [];
    let acIndex: number = acOffset;
    for (let cy = 0; cy < ny; cy++) {
      for (let cx = cy ? 0 : 1; cx * ny < nx * (ny - cy); cx++) {
        const nibble: number = ((hash[acStart + (acIndex >> 1)] >> ((acIndex & 1) << 2)) & 15);
        ac.push((nibble / 7.5 - 1) * scale);
        acIndex++;
      }
    }
    return ac;
  }
}
