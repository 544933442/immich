import { describe, expect, it } from 'vitest';
import {
  AI_DEDUP_ENCRYPTION_KEY_ENV,
  AiDedupCredentialError,
  decryptApiKey,
  encryptApiKey,
  getEncryptionKey,
  hasEncryptionKey,
  maskApiKey,
} from 'src/ai-dedup/credential.js';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';

const KEY = Buffer.alloc(32, 7);

describe('getEncryptionKey', () => {
  it('fails closed when the deployment key is missing', () => {
    expect(() => getEncryptionKey({})).toThrow(AiDedupCredentialError);
    try {
      getEncryptionKey({});
    } catch (error) {
      expect(error).toBeInstanceOf(AiDedupCredentialError);
      expect((error as AiDedupCredentialError).code).toBe(AiDedupErrorCode.EncryptionKeyMissing);
    }
    expect(hasEncryptionKey({})).toBe(false);
  });

  it('accepts 64-char hex, 32-byte base64, a raw 32-byte string, or derives from any value', () => {
    const hex = 'ab'.repeat(32);
    expect(getEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: hex })).toEqual(Buffer.from(hex, 'hex'));
    expect(getEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: KEY.toString('base64') })).toEqual(KEY);
    expect(getEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: 'a'.repeat(32) })).toEqual(
      Buffer.from('a'.repeat(32), 'utf8'),
    );

    const derived = getEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: 'short-but-stable' });
    expect(derived).toHaveLength(32);
    expect(derived).toEqual(getEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: 'short-but-stable' }));
    expect(hasEncryptionKey({ [AI_DEDUP_ENCRYPTION_KEY_ENV]: 'short-but-stable' })).toBe(true);
  });
});

describe('AES-256-GCM credential round trip', () => {
  it('encrypts and decrypts without ever storing the plaintext in the bundle', () => {
    const apiKey = 'sk-super-secret-value-3f2a';
    const bundle = encryptApiKey(apiKey, KEY);

    expect(decryptApiKey(bundle, KEY)).toBe(apiKey);
    expect(JSON.stringify(bundle)).not.toContain(apiKey);
    expect(bundle.masked).toBe(maskApiKey(apiKey));
    expect(bundle.v).toBe(1);
  });

  it('uses a fresh IV for every write', () => {
    const first = encryptApiKey('same-key', KEY);
    const second = encryptApiKey('same-key', KEY);
    expect(first.iv).not.toBe(second.iv);
    expect(first.cipher).not.toBe(second.cipher);
  });

  it('rejects a tampered auth tag and a wrong key', () => {
    const bundle = encryptApiKey('sk-test', KEY);
    const tampered = { ...bundle, tag: Buffer.alloc(16, 0).toString('base64') };
    expect(() => decryptApiKey(tampered, KEY)).toThrow();
    expect(() => decryptApiKey(bundle, Buffer.alloc(32, 9))).toThrow();
  });

  it('rejects an unsupported bundle version and a non-32-byte key', () => {
    const bundle = { ...encryptApiKey('sk-test', KEY), v: 2 };
    expect(() => decryptApiKey(bundle, KEY)).toThrow(AiDedupCredentialError);
    expect(() => encryptApiKey('sk-test', Buffer.alloc(16))).toThrow(AiDedupCredentialError);
  });
});

describe('maskApiKey', () => {
  it('keeps only the first three and last four characters', () => {
    expect(maskApiKey('sk-abcdefgh3f2a')).toBe('sk-••••••••3f2a');
  });

  it('returns a fully masked placeholder for short values', () => {
    expect(maskApiKey('short')).toBe('••••••••');
    expect(maskApiKey('')).toBe('••••••••');
  });
});
