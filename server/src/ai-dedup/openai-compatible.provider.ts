import { lookup } from 'node:dns/promises';
import { isIP } from 'node:net';
import { AiDedupErrorCode } from 'src/ai-dedup/dto.js';
import { AI_DEDUP_DEFAULT_PROMPT } from 'src/ai-dedup/constants.js';
import { extractJson } from 'src/ai-dedup/parse.js';
import { renderPrompt } from 'src/ai-dedup/prompt.js';
import type {
  AiDedupEvaluateInput,
  AiDedupModelConfig,
  AiDedupModelRawResponse,
  AiDedupProvider,
  AiDedupTestReason,
  AiDedupTestResult,
} from 'src/ai-dedup/provider.interface.js';

/**
A 32x32 solid-colour JPEG (generated with sharp) used only by `testConnection`.
Some providers (e.g. DeepSeek) reject degenerate 1x1 images with
"unsupported image" / "invalid base64 data" and return HTTP 400, which would
be misclassified as NO_VISION. No real user photo ever leaves the server
during a connectivity probe (technical design §8.1 / E7).
*/
export const TEST_IMAGE_BASE64 =
  '/9j/2wBDAAUDBAQEAwUEBAQFBQUGBwwIBwcHBw8LCwkMEQ8SEhEPERETFhwXExQaFRERGCEYGh0dHx8fExciJCIeJBweHx7/2wBDAQUFBQcGBw4ICA4eFBEUHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh7/wAARCAAgACADASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAP/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFgEBAQEAAAAAAAAAAAAAAAAAAAYH/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAwDAQACEQMRAD8AqAz9cAAAAAAP/9k=';

const CLOUD_METADATA_HOSTS = new Set<string>([
  'metadata.google.internal',
  'metadata',
  'instance-data',
  '169.254.169.254',
  '100.100.100.200',
]);

/** Explicit allowlist entry match, including `*.example.com` wildcards. */
export const hostMatches = (pattern: string, hostname: string): boolean => {
  const normalized = pattern.trim().toLowerCase();
  if (normalized === hostname) {
    return true;
  }
  if (normalized.startsWith('*.')) {
    const suffix = normalized.slice(1);
    return hostname.endsWith(suffix) && hostname.length > suffix.length;
  }
  return false;
};

const isPrivateIpv4 = (ip: string): boolean => {
  const parts = ip.split('.').map(Number);
  if (parts.length !== 4 || parts.some((part) => !Number.isSafeInteger(part) || part < 0 || part > 255)) {
    return true;
  }
  const [a, b] = parts as [number, number, number, number];
  if (a === 0 || a === 10 || a === 127 || a >= 224) {
    return true;
  }
  if (a === 169 && b === 254) {
    return true;
  }
  if (a === 172 && b >= 16 && b <= 31) {
    return true;
  }
  if (a === 192 && b === 168) {
    return true;
  }
  if (a === 100 && b >= 64 && b <= 127) {
    return true;
  }
  if (a === 192 && b === 0) {
    return true;
  }
  if (a === 198 && (b === 18 || b === 19)) {
    return true;
  }
  return false;
};

const isPrivateIpv6 = (ip: string): boolean => {
  const lower = ip.toLowerCase();
  if (lower === '::' || lower === '::1') {
    return true;
  }
  // IPv4-mapped IPv6 (::ffff:a.b.c.d) delegates to the IPv4 check (QA legacy item 2).
  const mapped = /^::ffff:(\d{1,3}(?:\.\d{1,3}){3})$/u.exec(lower);
  if (mapped) {
    return isPrivateIpv4(mapped[1] as string);
  }
  // fc00::/7 (unique local) and fe80::/10 (link local)
  return /^f[cd][0-9a-f]*:/u.test(lower) || /^fe[89ab][0-9a-f]*:/u.test(lower);
};

/** True for any private / loopback / link-local / reserved IP address. */
export function isBlockedIp(ip: string): boolean {
  const version = isIP(ip);
  if (version === 4) {
    return isPrivateIpv4(ip);
  }
  if (version === 6) {
    return isPrivateIpv6(ip);
  }
  return true;
}

/**
Synchronous SSRF hostname check (unit-testable without DNS).
Rejects IP literals, localhost/local/internal names, cloud metadata endpoints and
private ranges unless the hostname is explicitly allowlisted.
*/
export function isBlockedHostname(hostname: string, allowedHosts: readonly string[] = []): boolean {
  const host = hostname.toLowerCase().replace(/\.$/u, '').replaceAll(/^\[|\]$/gu, '');
  if (allowedHosts.some((pattern) => hostMatches(pattern, host))) {
    return false;
  }
  if (!host || CLOUD_METADATA_HOSTS.has(host)) {
    return true;
  }
  if (/(^|\.)localhost$|(^|\.)local$|(^|\.)internal$/u.test(host) || host === 'localhost') {
    return true;
  }
  // IP literals are rejected outright unless explicitly allowlisted (technical design §3.4.5).
  if (isIP(host) !== 0) {
    return true;
  }
  return false;
}

/**
Six-fold SSRF validation: scheme, hostname literal, private/metadata ranges, DNS
re-resolution, allowlist, and redirect refusal (redirects are handled by `fetch` with
`redirect: 'manual'`). Resolved private addresses are never echoed back to the caller.
*/
export async function validateBaseUrl(
  rawUrl: string,
  allowedHosts: readonly string[] = [],
): Promise<{ ok: boolean; reason?: string }> {
  let url: URL;
  try {
    url = new URL(rawUrl);
  } catch {
    return { ok: false, reason: 'INVALID_URL' };
  }

  const allowlist = allowedHosts.map((entry) => entry.trim().toLowerCase()).filter(Boolean);
  const hostname = url.hostname.toLowerCase().replaceAll(/^\[|\]$/gu, '');
  const explicitlyAllowed = allowlist.some((pattern) => hostMatches(pattern, hostname));

  // http is only permitted for an explicitly allowlisted self-hosted service (Q17).
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && explicitlyAllowed)) {
    return { ok: false, reason: 'INSECURE_PROTOCOL' };
  }
  if (!hostname) {
    return { ok: false, reason: 'MISSING_HOST' };
  }
  if (isBlockedHostname(hostname, allowlist)) {
    return { ok: false, reason: 'BLOCKED_HOST' };
  }
  if (allowlist.length > 0 && !explicitlyAllowed) {
    return { ok: false, reason: 'HOST_NOT_ALLOWED' };
  }

  // Second check after DNS resolution (DNS rebinding protection). A failed lookup is a
  // rejection, NOT a pass: fetch would re-resolve the name later and an attacker who
  // controls DNS can deliberately make the validation-time lookup fail while the
  // request-time lookup returns a private address.
  if (isIP(hostname) === 0) {
    try {
      const addresses = await lookup(hostname, { all: true, verbatim: true });
      for (const { address } of addresses) {
        if (isBlockedIp(address)) {
          return { ok: false, reason: 'PRIVATE_DNS_RESULT' };
        }
      }
    } catch {
      return { ok: false, reason: 'DNS_LOOKUP_FAILED' };
    }
  }

  return { ok: true };
}

export class AiDedupProviderError extends Error {
  constructor(
    public readonly code: AiDedupErrorCode,
    message: string,
    public readonly status?: number,
    public readonly network = false,
  ) {
    super(message);
    this.name = 'AiDedupProviderError';
  }
}

export function classifyProviderError(error: unknown, status?: number): AiDedupErrorCode {
  if (status !== undefined) {
    if (status >= 300 && status < 400) {
      return AiDedupErrorCode.SsrfBlocked;
    }
    if (status === 401 || status === 403) {
      return AiDedupErrorCode.ProviderError;
    }
    if (status === 408) {
      return AiDedupErrorCode.Timeout;
    }
    if ([400, 404, 422].includes(status)) {
      return AiDedupErrorCode.ModelNoVision;
    }
    if (status === 429 || status >= 500) {
      return AiDedupErrorCode.ProviderError;
    }
    return AiDedupErrorCode.ProviderError;
  }
  const name = error instanceof Error ? error.name : '';
  return name === 'AbortError' || name === 'TimeoutError'
    ? AiDedupErrorCode.Timeout
    : AiDedupErrorCode.ProviderError;
}

const delay = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));

interface ChatCompletionResponse {
  choices?: Array<{
    finish_reason?: string;
    message?: { content?: unknown; reasoning_content?: unknown };
  }>;
  usage?: {
    prompt_tokens?: number;
    completion_tokens?: number;
    completion_tokens_details?: { reasoning_tokens?: number };
  };
}

/** The only phase-1 provider: OpenAI-compatible `chat/completions` with vision input. */
export class OpenAiCompatibleProvider implements AiDedupProvider {
  readonly id = 'openai-compatible';

  async evaluate(input: AiDedupEvaluateInput, credential: string): Promise<AiDedupModelRawResponse> {
    const validation = await validateBaseUrl(input.baseURL, input.allowedHosts);
    if (!validation.ok) {
      throw new AiDedupProviderError(AiDedupErrorCode.SsrfBlocked, validation.reason ?? 'SSRF_BLOCKED');
    }
    const url = `${input.baseURL.replace(/\/+$/u, '')}/chat/completions`;
    return this.perform(url, input, credential);
  }

  async testConnection(credential: string, config: AiDedupModelConfig): Promise<AiDedupTestResult> {
    const started = Date.now();
    const validation = await validateBaseUrl(config.baseURL, config.allowedHosts);
    if (!validation.ok) {
      return { ok: false, reason: 'SSRF_BLOCKED', latencyMs: Date.now() - started };
    }

    // Real capability probe. The previous lightweight 1-image / 64-token probe passed on
    // reasoning models (e.g. DeepSeek) whose actual evaluations then returned empty
    // content for every group. Mirror the real evaluation shape (full prompt, a
    // typical group size, configured maxTokens) so a broken model is caught in settings
    // instead of after a page full of slow, empty calls.
    const images: AiDedupEvaluateInput['images'] = Array.from({ length: 6 }, (_, index) => ({
      index: index + 1,
      base64Jpeg: TEST_IMAGE_BASE64,
    }));
    const input: AiDedupEvaluateInput = {
      ...config,
      temperature: 0,
      timeoutMs: config.timeoutMs,
      maxTokens: Math.max(config.maxTokens, 512),
      systemPrompt: renderPrompt(AI_DEDUP_DEFAULT_PROMPT, {
        assetCount: images.length,
        keepCount: 1,
        strategyHint: '',
      }),
      userPrompt: `本组共 ${images.length} 张照片，按编号 1..${images.length} 评估；请按系统提示输出一个合法 JSON 对象。`,
      images,
    };

    try {
      const url = `${config.baseURL.replace(/\/+$/u, '')}/chat/completions`;
      const response = await this.perform(url, input, credential);
      let parsed: { results?: unknown };
      try {
        parsed = JSON.parse(extractJson(response.content)) as { results?: unknown };
      } catch {
        return { ok: false, reason: 'NO_VISION', latencyMs: Date.now() - started };
      }
      if (!Array.isArray(parsed.results) || parsed.results.length !== images.length) {
        return { ok: false, reason: 'NO_VISION', latencyMs: Date.now() - started };
      }
      return { ok: true, latencyMs: Date.now() - started };
    } catch (error) {
      const truncated =
        error instanceof AiDedupProviderError && error.code === AiDedupErrorCode.OutputTruncated;
      return {
        ok: false,
        reason: truncated ? 'NO_VISION' : this.toTestReason(error),
        latencyMs: Date.now() - started,
      };
    }
  }

  private async perform(
    url: string,
    input: AiDedupEvaluateInput,
    credential: string,
  ): Promise<AiDedupModelRawResponse> {
    let useResponseFormat = true;

    // At most one retry: network/408/429/5xx, or a 400 caused by an unsupported
    // `response_format` (which is then removed). 4xx auth errors are never retried.
    for (let attempt = 0; attempt < 2; attempt++) {
      const payload = this.buildPayload(input, useResponseFormat);
      try {
        const response = await fetch(url, {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${credential}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(input.timeoutMs),
          redirect: 'manual',
        });

        if (response.status >= 300 && response.status < 400) {
          throw new AiDedupProviderError(
            AiDedupErrorCode.SsrfBlocked,
            'Redirect refused',
            response.status,
          );
        }

        if (!response.ok) {
          const code = classifyProviderError(undefined, response.status);
          if (response.status === 400 && useResponseFormat) {
            useResponseFormat = false;
            continue;
          }
          if ((response.status === 408 || response.status === 429 || response.status >= 500) && attempt === 0) {
            await delay(500 + Math.floor(Math.random() * 200));
            continue;
          }
          // Only status/classification is recorded; headers and body are never logged.
          throw new AiDedupProviderError(code, `Provider returned HTTP ${response.status}`, response.status);
        }

        const body = (await response.json()) as ChatCompletionResponse;
        const choice = body.choices?.[0];
        const content = choice?.message?.content;
        // Reasoning models can spend the entire `max_tokens` budget on hidden
        // chain-of-thought and return an empty `content` with finish_reason=length.
        // Detect it here so the whole batch can degrade fast instead of burning
        // the same slow, empty call once per group.
        if (choice?.finish_reason === 'length' || choice?.finish_reason === 'max_tokens' || typeof content !== 'string' || content.trim() === '') {
          throw new AiDedupProviderError(
            AiDedupErrorCode.OutputTruncated,
            'Provider returned an empty or truncated completion',
            response.status,
          );
        }
        // A reasoning model can occasionally squeeze out a short JSON on a trivial
        // synthetic probe, so a single lucky probe is not proof the model is usable.
        // Non-reasoning vision models (qwen-vl, glm-4v, gpt-4o) never report
        // `reasoning_tokens`; any positive value means chain-of-thought competes
        // with the JSON budget and real duplicate groups (more images, longer
        // reasons) will truncate. Reject the model rather than mislead the admin.
        const reasoningTokens = Number(body.usage?.completion_tokens_details?.reasoning_tokens ?? 0);
        if (reasoningTokens > 0) {
          throw new AiDedupProviderError(
            AiDedupErrorCode.OutputTruncated,
            'Reasoning model output budget is not controllable',
            response.status,
          );
        }
        return {
          content,
          inputTokens: Number(body.usage?.prompt_tokens ?? 0),
          outputTokens: Number(body.usage?.completion_tokens ?? 0),
        };
      } catch (error) {
        if (error instanceof AiDedupProviderError) {
          if (
            attempt === 0 &&
            (error.code === AiDedupErrorCode.ProviderError || error.code === AiDedupErrorCode.Timeout)
          ) {
            await delay(500 + Math.floor(Math.random() * 200));
            continue;
          }
          throw error;
        }

        const code = classifyProviderError(error);
        if (attempt === 0) {
          await delay(500 + Math.floor(Math.random() * 200));
          continue;
        }
        throw new AiDedupProviderError(code, 'Provider request failed', undefined, true);
      }
    }

    throw new AiDedupProviderError(AiDedupErrorCode.ProviderError, 'Provider request failed', undefined, true);
  }

  private buildPayload(input: AiDedupEvaluateInput, useResponseFormat: boolean): Record<string, unknown> {
    return {
      model: input.model,
      temperature: 0,
      max_tokens: input.maxTokens,
      ...(useResponseFormat && { response_format: { type: 'json_object' } }),
      messages: [
        { role: 'system', content: input.systemPrompt },
        {
          role: 'user',
          content: [
            { type: 'text', text: input.userPrompt },
            ...input.images.map((image) => ({
              type: 'image_url',
              image_url: { url: `data:image/jpeg;base64,${image.base64Jpeg}`, detail: 'low' },
            })),
          ],
        },
      ],
    };
  }

  private toTestReason(error: unknown): AiDedupTestReason {
    if (!(error instanceof AiDedupProviderError)) {
      return 'UNKNOWN';
    }
    if (error.code === AiDedupErrorCode.SsrfBlocked) {
      return 'SSRF_BLOCKED';
    }
    if (error.code === AiDedupErrorCode.Timeout) {
      return 'TIMEOUT';
    }
    if (error.status === 401 || error.status === 403) {
      return 'AUTH';
    }
    if (error.code === AiDedupErrorCode.ModelNoVision || error.status === 400) {
      return 'NO_VISION';
    }
    return error.network ? 'NETWORK' : 'UNKNOWN';
  }
}
