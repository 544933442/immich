/**
Dependency-free concurrency, circuit-breaking, quota, lazy-TTL and cache-key helpers.
Keeping these local avoids adding `p-limit` / `opossum` to package.json, and lets unit
tests exercise the pure computations without loading the NestJS dependency graph.
*/
import { createHash } from 'node:crypto';
import { AI_DEDUP_PROMPT_VERSION } from 'src/ai-dedup/constants.js';
import type { AiDedupImagePath } from 'src/ai-dedup/image.js';

export class Semaphore {
  private active = 0;
  private readonly queue: Array<() => void> = [];

  constructor(private readonly max: number) {}

  async run<T>(task: () => Promise<T>): Promise<T> {
    await this.acquire();
    try {
      return await task();
    } finally {
      this.release();
    }
  }

  private acquire(): Promise<void> {
    if (this.active < this.max) {
      this.active++;
      return Promise.resolve();
    }
    return new Promise<void>((resolve) => {
      this.queue.push(resolve);
    });
  }

  private release(): void {
    const next = this.queue.shift();
    if (next) {
      // Hand the slot directly to the waiter; `active` stays unchanged.
      next();
      return;
    }
    this.active = Math.max(0, this.active - 1);
  }
}

export class CircuitBreaker {
  private failures = 0;
  /** `null` means never opened; a numeric value is the timestamp the window started. */
  private openedAt: number | null = null;
  private probeInFlight = false;

  constructor(
    private readonly threshold = 5,
    private readonly openDurationMs = 60_000,
  ) {}

  isOpen(now: number = Date.now()): boolean {
    if (this.openedAt === null) {
      return false;
    }
    return now - this.openedAt < this.openDurationMs;
  }

  /** Allows exactly one probe request once the open window has elapsed. */
  canRequest(now: number = Date.now()): boolean {
    if (this.openedAt === null) {
      return true;
    }
    if (this.isOpen(now)) {
      return false;
    }
    if (this.probeInFlight) {
      return false;
    }
    this.probeInFlight = true;
    return true;
  }

  recordSuccess(): void {
    this.reset();
  }

  recordFailure(now: number = Date.now()): void {
    this.failures++;
    if (!(this.failures >= this.threshold)) {
      return;
    }

    this.openedAt = now;
    this.probeInFlight = false;
  }

  /** Used by `autoDisableOnLimit` so quota exhaustion stops all external requests in-process. */
  forceOpen(now: number = Date.now()): void {
    this.openedAt = now;
    this.probeInFlight = false;
  }

  reset(): void {
    this.failures = 0;
    this.openedAt = null;
    this.probeInFlight = false;
  }

  get state(): 'closed' | 'open' | 'half-open' {
    if (this.openedAt === null) {
      return 'closed';
    }
    return this.isOpen() ? 'open' : 'half-open';
  }
}

export const isQuotaExceeded = (used: number, limit: number): boolean => limit > 0 && used >= limit;

/** Lazy TTL: expired rows are simply not returned (and are removed on the next write). */
export const isFresh = (createdAt: string | Date, ttlDays: number, now: number = Date.now()): boolean => {
  const timestamp = typeof createdAt === 'string' ? Date.parse(createdAt) : createdAt.getTime();
  if (!Number.isFinite(timestamp)) {
    return false;
  }
  const age = now - timestamp;
  return age >= 0 && age <= ttlDays * 86_400_000;
};

/**
Millisecond-granular freshness, used for the short-lived degraded cache: a failed
evaluation is reused briefly so a failing/unsupported model cannot be billed on
every page load (force=true still bypasses it).
*/
export const isFreshWithinMs = (createdAt: string | Date, ttlMs: number, now: number = Date.now()): boolean => {
  const timestamp = typeof createdAt === 'string' ? Date.parse(createdAt) : createdAt.getTime();
  if (!Number.isFinite(timestamp)) {
    return false;
  }
  const age = now - timestamp;
  return age >= 0 && age <= ttlMs;
};

const sha256 = (text: string): string => createHash('sha256').update(text).digest('hex');

const normalizeBaseUrl = (baseURL: string): string => {
  try {
    const url = new URL(baseURL);
    return `${url.origin}${url.pathname.replace(/\/+$/u, '')}`;
  } catch {
    return baseURL.trim().replace(/\/+$/u, '');
  }
};

/** memberHash = sha256(sorted asset ids + asset.updateId + thumbnail/preview updateId). */
export function buildMemberHash(
  assets: Array<{ id: string; updateId: string }>,
  imagePaths: AiDedupImagePath[],
): string {
  const assetPart = assets.map((asset) => `${asset.id}:${asset.updateId}`).sort().join('|');
  const filePart = imagePaths
    .map((path) => `${path.assetId}:${path.updateId ?? ''}`)
    .sort()
    .join('|');
  return sha256(`${assetPart}|${filePart}`);
}

export interface AiDedupCacheKeyInput {
  provider: string;
  baseURL: string;
  model: string;
  promptVersion: string;
  promptTemplate: string;
  strategyHint: string;
  keepCount: number;
  maxImagesPerGroup: number;
  maxImageDimension: number;
  imageQuality: number;
  temperature: number;
  memberHash: string;
  ownerId: string;
  /** [ai-dedup] Changes `needsManualReview` and therefore the persisted recommendation set. */
  lowConfidenceThreshold: number;
}

/** The 14-dimension cache key (technical design §3.3.3 + lowConfidenceThreshold); a 64-char sha256 hex string. */
export function buildAiDedupCacheKey(input: AiDedupCacheKeyInput): string {
  return sha256(
    [
      input.provider,
      normalizeBaseUrl(input.baseURL),
      input.model,
      input.promptVersion || AI_DEDUP_PROMPT_VERSION,
      sha256(input.promptTemplate),
      sha256(input.strategyHint.trim()),
      String(input.keepCount),
      String(input.maxImagesPerGroup),
      String(input.maxImageDimension),
      String(input.imageQuality),
      String(input.temperature),
      input.memberHash,
      input.ownerId,
      String(input.lowConfidenceThreshold),
    ].join('|'),
  );
}
