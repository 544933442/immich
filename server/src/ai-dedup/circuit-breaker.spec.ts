import { describe, expect, it } from 'vitest';
import {
  CircuitBreaker,
  Semaphore,
  buildAiDedupCacheKey,
  buildMemberHash,
  isFresh,
  isFreshWithinMs,
  isQuotaExceeded,
  type AiDedupCacheKeyInput,
} from 'src/ai-dedup/circuit-breaker.js';
import { AI_DEDUP_DEFAULT_PROMPT, AI_DEDUP_PROMPT_VERSION } from 'src/ai-dedup/constants.js';
import type { AiDedupImagePath } from 'src/ai-dedup/image.js';

const cacheKeyInput = (overrides: Partial<AiDedupCacheKeyInput> = {}): AiDedupCacheKeyInput => ({
  provider: 'openai-compatible',
  baseURL: 'https://api.example.com/v1',
  model: 'gpt-4o-mini',
  promptVersion: AI_DEDUP_PROMPT_VERSION,
  promptTemplate: AI_DEDUP_DEFAULT_PROMPT,
  strategyHint: '',
  keepCount: 1,
  maxImagesPerGroup: 8,
  maxImageDimension: 1024,
  imageQuality: 80,
  temperature: 0,
  maxTokens: 800,
  memberHash: 'member-hash',
  ownerId: '00000000-0000-4000-8000-000000000001',
  lowConfidenceThreshold: 0.5,
  ...overrides,
});

describe('Semaphore', () => {
  it('never exceeds its configured concurrency', async () => {
    const semaphore = new Semaphore(2);
    let active = 0;
    let peak = 0;

    const task = () =>
      semaphore.run(async () => {
        active++;
        peak = Math.max(peak, active);
        await new Promise<void>((resolve) => setTimeout(resolve, 5));
        active--;
      });

    await Promise.all([task(), task(), task(), task(), task()]);
    expect(peak).toBe(2);
    expect(active).toBe(0);
  });

  it('releases the slot even when the task throws', async () => {
    const semaphore = new Semaphore(1);
    await expect(semaphore.run(() => Promise.reject(new Error('boom')))).rejects.toThrow('boom');
    await expect(semaphore.run(() => Promise.resolve(42))).resolves.toBe(42);
  });
});

describe('CircuitBreaker', () => {
  it('opens after the threshold and allows exactly one probe after the window', () => {
    const breaker = new CircuitBreaker(2, 1000);
    expect(breaker.state).toBe('closed');
    expect(breaker.canRequest(1000)).toBe(true);

    breaker.recordFailure(1000);
    breaker.recordFailure(1000);
    expect(breaker.isOpen(1000)).toBe(true);
    expect(breaker.canRequest(1000)).toBe(false);
    expect(breaker.canRequest(1500)).toBe(false);

    // Window elapsed: one half-open probe only.
    expect(breaker.canRequest(2001)).toBe(true);
    expect(breaker.canRequest(2001)).toBe(false);
    expect(breaker.state).toBe('half-open');
  });

  it('resets on success and re-arms after a failed probe', () => {
    const breaker = new CircuitBreaker(1, 1000);
    breaker.recordFailure(1000);
    expect(breaker.canRequest(2001)).toBe(true);
    breaker.recordSuccess();
    expect(breaker.state).toBe('closed');
    expect(breaker.canRequest(2001)).toBe(true);

    breaker.forceOpen(3000);
    expect(breaker.canRequest(3000)).toBe(false);
    breaker.reset();
    expect(breaker.canRequest(3000)).toBe(true);
  });
});

describe('quota / lazy TTL helpers', () => {
  it('treats a positive limit as exhausted only at or above the used count', () => {
    expect(isQuotaExceeded(199, 200)).toBe(false);
    expect(isQuotaExceeded(200, 200)).toBe(true);
    expect(isQuotaExceeded(500, 0)).toBe(false);
  });

  it('accepts fresh rows and rejects expired / future / invalid timestamps', () => {
    const now = Date.parse('2026-11-13T00:00:00.000Z');
    expect(isFresh('2026-11-01T00:00:00.000Z', 30, now)).toBe(true);
    expect(isFresh('2026-09-01T00:00:00.000Z', 30, now)).toBe(false);
    expect(isFresh(new Date(now), 30, now)).toBe(true);
    expect(isFresh('not-a-date', 30, now)).toBe(false);
    expect(isFresh('2026-11-14T00:00:00.000Z', 30, now)).toBe(false);
  });

  it('isFreshWithinMs bounds the short-lived degraded cache in milliseconds', () => {
    const now = Date.parse('2026-11-13T12:00:00.000Z');
    expect(isFreshWithinMs('2026-11-13T11:30:00.000Z', 60 * 60_000, now)).toBe(true);
    expect(isFreshWithinMs('2026-11-13T10:00:00.000Z', 60 * 60_000, now)).toBe(false);
    expect(isFreshWithinMs('not-a-date', 60 * 60_000, now)).toBe(false);
    expect(isFreshWithinMs('2026-11-13T13:00:00.000Z', 60 * 60_000, now)).toBe(false);
  });
});

describe('buildMemberHash', () => {
  const paths: AiDedupImagePath[] = [
    { assetId: 'a', path: '/a.jpg', type: 'preview', updateId: 'f1' },
    { assetId: 'b', path: '/b.jpg', type: 'thumbnail', updateId: 'f2' },
  ];
  const assets = [
    { id: 'a', updateId: 'u1' },
    { id: 'b', updateId: 'u2' },
  ];

  it('is deterministic and independent of input order', () => {
    expect(buildMemberHash(assets, paths)).toBe(buildMemberHash(assets.toReversed(), paths.toReversed()));
    expect(buildMemberHash(assets, paths)).toMatch(/^[0-9a-f]{64}$/u);
  });

  it('changes when a member or a thumbnail file is updated', () => {
    expect(buildMemberHash(assets, paths)).not.toBe(
      buildMemberHash([{ id: 'a', updateId: 'u3' }, assets[1]], paths),
    );
    expect(buildMemberHash(assets, paths)).not.toBe(
      buildMemberHash(assets, [{ ...paths[0], updateId: 'f3' }, paths[1]]),
    );
  });
});

describe('buildAiDedupCacheKey (14 dimensions)', () => {
  it('returns a stable 64-char sha256 hex', () => {
    const key = buildAiDedupCacheKey(cacheKeyInput());
    expect(key).toMatch(/^[0-9a-f]{64}$/u);
    expect(buildAiDedupCacheKey(cacheKeyInput())).toBe(key);
  });

  it('invalidates on every dimension that changes the evaluation', () => {
    const baseline = buildAiDedupCacheKey(cacheKeyInput());
    const variants: Partial<AiDedupCacheKeyInput>[] = [
      { provider: 'other' },
      { baseURL: 'https://api.example.com/v2' },
      { model: 'gpt-4o' },
      { promptVersion: 'ai-dedup-prompt-v1.1' },
      { promptTemplate: `${AI_DEDUP_DEFAULT_PROMPT}\n` },
      { strategyHint: '优先保留横构图' },
      { keepCount: 2 },
      { maxImagesPerGroup: 4 },
      { maxImageDimension: 512 },
      { imageQuality: 60 },
      { temperature: 0.1 },
      { maxTokens: 1600 },
      { memberHash: 'different-members' },
      { ownerId: '00000000-0000-4000-8000-000000000002' },
      // The threshold decides needsManualReview and therefore the stored recommendation set.
      { lowConfidenceThreshold: 0.8 },
    ];
    for (const variant of variants) {
      expect(buildAiDedupCacheKey(cacheKeyInput(variant)), JSON.stringify(variant)).not.toBe(baseline);
    }
  });

  it('normalizes a trailing slash in baseURL and trims strategyHint whitespace', () => {
    expect(buildAiDedupCacheKey(cacheKeyInput({ baseURL: 'https://api.example.com/v1/' }))).toBe(
      buildAiDedupCacheKey(cacheKeyInput()),
    );
    expect(buildAiDedupCacheKey(cacheKeyInput({ strategyHint: '  ' }))).toBe(
      buildAiDedupCacheKey(cacheKeyInput()),
    );
  });
});
