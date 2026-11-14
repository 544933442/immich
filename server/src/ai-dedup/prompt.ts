import { AI_DEDUP_DEFAULT_PROMPT, AI_DEDUP_PROMPT_VERSION } from 'src/ai-dedup/constants.js';

/**
Fixed-template renderer. Only three exact string placeholders are substituted; no template
engine is involved, so a malicious `strategyHint` can never execute code (technical design §12).
*/
export function renderPrompt(
  template: string,
  options: { assetCount: number; keepCount: number; strategyHint: string },
): string {
  // Replacer callbacks keep untrusted values out of the replacement-pattern grammar:
  // a `strategyHint` containing `$&` / `$'` can never inject template syntax.
  return template
    .replaceAll('{{asset_count}}', () => String(options.assetCount))
    .replaceAll('{{keep_count}}', () => String(options.keepCount))
    .replaceAll('{{strategy_hint}}', () => options.strategyHint.trim());
}

export function promptVersion(): string {
  return AI_DEDUP_PROMPT_VERSION;
}

/** Short, human-readable summary of the active strategy for the duplicates page. */
export function strategySummary(hint: string): string {
  const text = hint.trim();
  if (!text) {
    return '默认策略（清晰度 / 画质 / 构图）';
  }
  const chars = [...text];
  return `${chars.slice(0, 40).join('')}${chars.length > 40 ? '…' : ''}`;
}

/** Line-level difference summary used by the "restore default prompt" confirmation dialog. */
export function diffSummary(current: string, defaults: string = AI_DEDUP_DEFAULT_PROMPT): string {
  if (current === defaults) {
    return '与默认提示词一致';
  }

  const currentLines = new Set(current.split(/\r?\n/u));
  const defaultLines = new Set(defaults.split(/\r?\n/u));
  const added = [...currentLines].filter((line) => !defaultLines.has(line)).length;
  const removed = [...defaultLines].filter((line) => !currentLines.has(line)).length;
  return `与默认提示词存在 ${added} 行新增、${removed} 行删减`;
}
