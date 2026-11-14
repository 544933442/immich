import { createCipheriv, createDecipheriv, createHash, randomBytes } from 'node:crypto';
import { SystemMetadataKey } from 'src/enum.js';
import type { SystemMetadataRepository } from 'src/repositories/system-metadata.repository.js';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';

/** Process-level encryption key; intentionally NOT the per-start random workflow jwtSecret. */
export const AI_DEDUP_ENCRYPTION_KEY_ENV = 'IMMICH_AI_DEDUP_ENCRYPTION_KEY';

/** AAD binds the ciphertext to the global credential slot so it cannot be swapped between keys. */
const AAD = Buffer.from('__global__', 'utf8');
const ALGORITHM = 'aes-256-gcm';
const IV_BYTES = 12;
const KEY_BYTES = 32;

export interface AiDedupCipherBundle {
  v: number;
  iv: string;
  tag: string;
  cipher: string;
  masked: string;
  updatedAt: string;
}

export class AiDedupCredentialError extends Error {
  constructor(public readonly code: AiDedupErrorCode, message: string) {
    super(message);
    this.name = 'AiDedupCredentialError';
  }
}

/**
Resolve the persistent 32-byte key. Accepts 64-char hex, base64 that decodes to 32 bytes,
a raw 32-byte UTF-8 string, or derives a stable 32-byte key from any other non-empty value.
A missing value is a hard error (Q16): never silently fall back to an ephemeral key.
*/
export function getEncryptionKey(env: NodeJS.ProcessEnv = process.env): Buffer {
  const raw = env[AI_DEDUP_ENCRYPTION_KEY_ENV]?.trim();
  if (!raw) {
    throw new AiDedupCredentialError(
      AiDedupErrorCode.EncryptionKeyMissing,
      `${AI_DEDUP_ENCRYPTION_KEY_ENV} is not set; AI dedup credentials cannot be stored`,
    );
  }

  if (/^[0-9a-fA-F]{64}$/u.test(raw)) {
    return Buffer.from(raw, 'hex');
  }

  const fromBase64 = Buffer.from(raw, 'base64');
  if (fromBase64.length === KEY_BYTES) {
    return fromBase64;
  }

  if (Buffer.byteLength(raw, 'utf8') === KEY_BYTES) {
    return Buffer.from(raw, 'utf8');
  }

  return createHash('sha256').update(raw, 'utf8').digest();
}

/** True when the deployment supplied an encryption key (used to gate `enabled`). */
export function hasEncryptionKey(env: NodeJS.ProcessEnv = process.env): boolean {
  try {
    getEncryptionKey(env);
    return true;
  } catch {
    return false;
  }
}

/** Keep first 3 + last 4 characters, e.g. `sk-••••••••3f2a`. */
export function maskApiKey(plain: string): string {
  const chars = [...plain];
  if (chars.length <= 7) {
    return '••••••••';
  }
  return `${chars.slice(0, 3).join('')}••••••••${chars.slice(-4).join('')}`;
}

export function encryptApiKey(plain: string, key: Buffer = getEncryptionKey()): AiDedupCipherBundle {
  if (key.length !== KEY_BYTES) {
    throw new AiDedupCredentialError(AiDedupErrorCode.EncryptionKeyMissing, 'Encryption key must be 32 bytes');
  }

  const iv = randomBytes(IV_BYTES);
  const cipher = createCipheriv(ALGORITHM, key, iv);
  cipher.setAAD(AAD);
  const encrypted = Buffer.concat([cipher.update(plain, 'utf8'), cipher.final()]);

  return {
    v: 1,
    iv: iv.toString('base64'),
    tag: cipher.getAuthTag().toString('base64'),
    cipher: encrypted.toString('base64'),
    masked: maskApiKey(plain),
    updatedAt: new Date().toISOString(),
  };
}

export function decryptApiKey(bundle: AiDedupCipherBundle, key: Buffer = getEncryptionKey()): string {
  if (key.length !== KEY_BYTES) {
    throw new AiDedupCredentialError(AiDedupErrorCode.EncryptionKeyMissing, 'Encryption key must be 32 bytes');
  }
  if (bundle.v !== 1) {
    throw new AiDedupCredentialError(AiDedupErrorCode.NotConfigured, 'Unsupported credential bundle version');
  }

  const decipher = createDecipheriv(ALGORITHM, key, Buffer.from(bundle.iv, 'base64'));
  decipher.setAAD(AAD);
  decipher.setAuthTag(Buffer.from(bundle.tag, 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(bundle.cipher, 'base64')), decipher.final()]).toString('utf8');
}

/**
Thin wrapper around `system_metadata['ai-dedup-credential']`.
Plaintext and ciphertext never leave this class except through `get()` (in-memory only).
*/
export class AiDedupCredentialStore {
  private cached: string | null = null;

  constructor(private readonly metadata: SystemMetadataRepository) {}

  async status(): Promise<{ configured: boolean; masked: string; updatedAt: string }> {
    const bundle = await this.readBundle();
    return bundle
      ? { configured: true, masked: bundle.masked, updatedAt: bundle.updatedAt }
      : { configured: false, masked: '', updatedAt: '' };
  }

  async has(): Promise<boolean> {
    return (await this.readBundle()) !== null;
  }

  async put(apiKey: string): Promise<{ configured: boolean; masked: string; updatedAt: string }> {
    const key = getEncryptionKey();
    const bundle = encryptApiKey(apiKey, key);
    await this.metadata.set(SystemMetadataKey.AiDedupCredential, bundle);
    this.cached = apiKey;
    return { configured: true, masked: bundle.masked, updatedAt: bundle.updatedAt };
  }

  /** Decrypted plaintext; throws a coded error when missing/undecryptable so callers can degrade. */
  async get(): Promise<string> {
    if (this.cached !== null) {
      return this.cached;
    }

    const bundle = await this.readBundle();
    if (!bundle) {
      throw new AiDedupCredentialError(AiDedupErrorCode.NotConfigured, 'AI dedup credential is not configured');
    }

    // Decryption failure (e.g. key rotation) is treated as "not configured", never fatal.
    const plaintext = decryptApiKey(bundle, getEncryptionKey());
    this.cached = plaintext;
    return plaintext;
  }

  async clear(): Promise<void> {
    this.cached = null;
    await this.metadata.delete(SystemMetadataKey.AiDedupCredential);
  }

  private async readBundle(): Promise<AiDedupCipherBundle | null> {
    const value = await this.metadata.get(SystemMetadataKey.AiDedupCredential);
    if (!value || typeof value !== 'object' || !('cipher' in value)) {
      return null;
    }
    return value as unknown as AiDedupCipherBundle;
  }
}
