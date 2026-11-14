import { afterEach, describe, expect, it, vi } from 'vitest';
import { lookup } from 'node:dns/promises';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';
import { OpenAiCompatibleProvider } from 'src/ai-dedup/openai-compatible.provider.js';
import type { AiDedupEvaluateInput } from 'src/ai-dedup/provider.interface.js';

// Deterministic DNS: no external network is touched by any test here.
vi.mock('node:dns/promises', () => ({
  lookup: vi.fn().mockResolvedValue([{ address: '93.184.216.34', family: 4 }]),
}));

const mockLookup = vi.mocked(lookup);

const input = (): AiDedupEvaluateInput => ({
  baseURL: 'https://api.example.com/v1',
  model: 'vision-model',
  timeoutMs: 5000,
  maxTokens: 800,
  temperature: 0,
  allowedHosts: ['api.example.com'],
  systemPrompt: 'output json',
  userPrompt: 'evaluate',
  images: [{ index: 1, base64Jpeg: 'AAAA' }],
});

const respond = (body: unknown) =>
  vi.fn().mockResolvedValue({
    ok: true,
    status: 200,
    json: () => Promise.resolve(body),
  });

afterEach(() => {
  vi.unstubAllGlobals();
  vi.clearAllMocks();
  mockLookup.mockResolvedValue([{ address: '93.184.216.34', family: 4 }] as never);
});

describe('reasoning-model output truncation', () => {
  it('rejects an empty completion with finish_reason=length instead of treating it as a parse error', async () => {
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'length', message: { content: '' } }],
        usage: { prompt_tokens: 2000, completion_tokens: 800 },
      }),
    );

    await expect(new OpenAiCompatibleProvider().evaluate(input(), 'key')).rejects.toMatchObject({
      code: AiDedupErrorCode.OutputTruncated,
    });
  });

  it('rejects whitespace-only content even without an explicit finish_reason', async () => {
    vi.stubGlobal(
      'fetch',
      respond({ choices: [{ message: { content: ' '.repeat(3) } }], usage: { completion_tokens: 800 } }),
    );

    await expect(new OpenAiCompatibleProvider().evaluate(input(), 'key')).rejects.toMatchObject({
      code: AiDedupErrorCode.OutputTruncated,
    });
  });

  it('accepts a normal non-empty completion', async () => {
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'stop', message: { content: '{"results":[]}' } }],
        usage: { prompt_tokens: 2000, completion_tokens: 60 },
      }),
    );

    await expect(new OpenAiCompatibleProvider().evaluate(input(), 'key')).resolves.toMatchObject({
      content: '{"results":[]}',
      outputTokens: 60,
    });
  });

  it('rejects a lucky short answer when hidden reasoning still consumed the budget', async () => {
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'stop', message: { content: '{"results":[]}' } }],
        usage: { completion_tokens: 800, completion_tokens_details: { reasoning_tokens: 790 } },
      }),
    );

    await expect(new OpenAiCompatibleProvider().evaluate(input(), 'key')).rejects.toMatchObject({
      code: AiDedupErrorCode.OutputTruncated,
    });
  });
});

describe('testConnection real capability probe', () => {
  const config = {
    baseURL: 'https://api.example.com/v1',
    model: 'vision-model',
    timeoutMs: 30_000,
    maxTokens: 800,
    temperature: 0,
    allowedHosts: ['api.example.com'],
  };

  it('fails early when the model spends the whole budget on hidden reasoning', async () => {
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'length', message: { content: '' } }],
        usage: { completion_tokens: 800 },
      }),
    );

    await expect(new OpenAiCompatibleProvider().testConnection('key', config)).resolves.toMatchObject({
      ok: false,
      reason: 'NO_VISION',
    });
  });

  it('fails when the model returns non-JSON or a payload without results', async () => {
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'stop', message: { content: '抱歉，我无法评估。' } }],
        usage: { completion_tokens: 20 },
      }),
    );

    await expect(new OpenAiCompatibleProvider().testConnection('key', config)).resolves.toMatchObject({
      ok: false,
      reason: 'NO_VISION',
    });
  });

  it('passes only when a parseable results array is returned', async () => {
    const json = JSON.stringify({
      version: 'ai-dedup-prompt-v1.0',
      strategyApplied: false,
      results: Array.from({ length: 6 }, (_, index) => ({
        index: index + 1,
        scores: { clarity: 8, quality: 8, composition: 8 },
        weightedScore: 8,
        confidence: 0.9,
        reason: 'ok',
        defects: [],
      })),
      recommendedKeepIndices: [1],
      summary: 'ok',
    });
    vi.stubGlobal(
      'fetch',
      respond({
        choices: [{ finish_reason: 'stop', message: { content: json } }],
        usage: { completion_tokens: 200 },
      }),
    );

    await expect(new OpenAiCompatibleProvider().testConnection('key', config)).resolves.toMatchObject({
      ok: true,
    });
  });
});
