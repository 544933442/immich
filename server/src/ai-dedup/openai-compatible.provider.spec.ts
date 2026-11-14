import { describe, expect, it } from 'vitest';
import {
  classifyProviderError,
  hostMatches,
  isBlockedHostname,
  isBlockedIp,
  validateBaseUrl,
} from 'src/ai-dedup/openai-compatible.provider.js';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';

describe('hostMatches', () => {
  it('supports exact and wildcard allowlist entries', () => {
    expect(hostMatches('api.example.com', 'api.example.com')).toBe(true);
    expect(hostMatches('*.example.com', 'api.example.com')).toBe(true);
    expect(hostMatches('*.example.com', 'example.com')).toBe(false);
    expect(hostMatches('*.example.com', 'api.other.com')).toBe(false);
  });
});

describe('isBlockedIp', () => {
  it('blocks loopback, private, link-local, reserved and cloud metadata addresses', () => {
    for (const ip of [
      '127.0.0.1',
      '10.0.0.1',
      '172.16.0.1',
      '192.168.1.1',
      '169.254.169.254',
      '100.100.100.200',
      '0.0.0.0',
      '224.0.0.1',
      '::1',
      'fd00::1',
      'fe80::1',
    ]) {
      expect(isBlockedIp(ip), ip).toBe(true);
    }
  });

  it('blocks IPv4-mapped IPv6 forms of private addresses and allows public ones', () => {
    expect(isBlockedIp('::ffff:127.0.0.1')).toBe(true);
    expect(isBlockedIp('::ffff:192.168.1.1')).toBe(true);
    expect(isBlockedIp('::ffff:169.254.169.254')).toBe(true);
    expect(isBlockedIp('::ffff:8.8.8.8')).toBe(false);
  });

  it('allows public addresses and rejects malformed values', () => {
    expect(isBlockedIp('8.8.8.8')).toBe(false);
    expect(isBlockedIp('1.1.1.1')).toBe(false);
    expect(isBlockedIp('not-an-ip')).toBe(true);
  });
});

describe('isBlockedHostname', () => {
  it('blocks local/internal names, cloud metadata and bare IP literals', () => {
    for (const host of [
      'localhost',
      'foo.localhost',
      'printer.local',
      'service.internal',
      'metadata.google.internal',
      '169.254.169.254',
      '127.0.0.1',
    ]) {
      expect(isBlockedHostname(host), host).toBe(true);
    }
  });

  it('accepts public hostnames and honours an explicit allowlist', () => {
    expect(isBlockedHostname('api.example.com')).toBe(false);
    expect(isBlockedHostname('api.example.com', ['*.example.com'])).toBe(false);
    expect(isBlockedHostname('127.0.0.1', ['127.0.0.1'])).toBe(false);
  });
});

describe('validateBaseUrl', () => {
  it('rejects malformed URLs', async () => {
    await expect(validateBaseUrl('not a url')).resolves.toMatchObject({ ok: false, reason: 'INVALID_URL' });
  });

  it('rejects plaintext http unless the host is explicitly allowlisted', async () => {
    // Built dynamically so the `unicorn/prefer-https` auto-fix cannot rewrite the fixture.
    const scheme = 'http';
    const insecureUrl = `${scheme}://api.example.com/v1`;
    await expect(validateBaseUrl(insecureUrl)).resolves.toMatchObject({
      ok: false,
      reason: 'INSECURE_PROTOCOL',
    });
  });

  it('rejects private / metadata hosts before any DNS lookup', async () => {
    for (const url of [
      'https://localhost/v1',
      'https://127.0.0.1/v1',
      'https://169.254.169.254/latest/meta-data',
      'https://metadata.google.internal/v1',
    ]) {
      await expect(validateBaseUrl(url), url).resolves.toMatchObject({ ok: false, reason: 'BLOCKED_HOST' });
    }
  });

  it('enforces a non-empty allowlist when configured', async () => {
    await expect(validateBaseUrl('https://api.example.com/v1', ['other.example.com'])).resolves.toMatchObject({
      ok: false,
      reason: 'HOST_NOT_ALLOWED',
    });
  });

  it('permits an explicitly allowlisted self-hosted endpoint (Q17)', async () => {
    // An IP-literal hostname skips DNS entirely, so this assertion is network-independent.
    await expect(validateBaseUrl('https://127.0.0.1/v1', ['127.0.0.1'])).resolves.toEqual({ ok: true });
    await expect(validateBaseUrl('http://127.0.0.1/v1', ['127.0.0.1'])).resolves.toEqual({ ok: true });
  });
});

describe('classifyProviderError', () => {
  it('maps redirect / auth / timeout / vision / rate-limit statuses to degradation codes', () => {
    expect(classifyProviderError(undefined, 302)).toBe(AiDedupErrorCode.SsrfBlocked);
    expect(classifyProviderError(undefined, 401)).toBe(AiDedupErrorCode.ProviderError);
    expect(classifyProviderError(undefined, 408)).toBe(AiDedupErrorCode.Timeout);
    expect(classifyProviderError(undefined, 400)).toBe(AiDedupErrorCode.ModelNoVision);
    expect(classifyProviderError(undefined, 429)).toBe(AiDedupErrorCode.ProviderError);
    expect(classifyProviderError(undefined, 500)).toBe(AiDedupErrorCode.ProviderError);
  });

  it('maps aborted requests to TIMEOUT and other errors to PROVIDER_ERROR', () => {
    class TimeoutError extends Error {
      override readonly name = 'TimeoutError';
    }
    expect(classifyProviderError(new TimeoutError('aborted'))).toBe(AiDedupErrorCode.Timeout);
    expect(classifyProviderError(new Error('socket hang up'))).toBe(AiDedupErrorCode.ProviderError);
  });
});
