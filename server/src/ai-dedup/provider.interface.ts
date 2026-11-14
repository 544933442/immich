/**
Provider abstraction for the AI dedup module. Phase 1 ships exactly one implementation
(`openai-compatible`), but the interface keeps the door open for additional protocols.
*/

export interface AiDedupModelConfig {
  baseURL: string;
  model: string;
  timeoutMs: number;
  maxTokens: number;
  temperature: number;
  allowedHosts: string[];
}

/** Everything the provider needs to build one chat/completions request. */
export interface AiDedupEvaluateInput extends AiDedupModelConfig {
  systemPrompt: string;
  userPrompt: string;
  images: Array<{ index: number; base64Jpeg: string }>;
  temperature: 0;
}

export interface AiDedupModelRawResponse {
  content: string;
  inputTokens: number;
  outputTokens: number;
}

export type AiDedupTestReason = 'AUTH' | 'TIMEOUT' | 'NO_VISION' | 'NETWORK' | 'SSRF_BLOCKED' | 'UNKNOWN';

export interface AiDedupTestResult {
  ok: boolean;
  /** Omitted on success; present with a classified reason on failure. */
  reason?: AiDedupTestReason;
  latencyMs: number;
}

export interface AiDedupProvider {
  readonly id: string;
  evaluate(input: AiDedupEvaluateInput, credential: string): Promise<AiDedupModelRawResponse>;
  testConnection(credential: string, config: AiDedupModelConfig): Promise<AiDedupTestResult>;
}
