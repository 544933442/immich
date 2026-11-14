import { describe, expect, it } from 'vitest';
import { AI_DEDUP_DEFAULT_PROMPT, AI_DEDUP_PROMPT_VERSION } from 'src/ai-dedup/constants.js';
import { diffSummary, promptVersion, renderPrompt, strategySummary } from 'src/ai-dedup/prompt.js';

describe('constants (single source of truth)', () => {
  it('exposes a fixed Chinese prompt with exactly the three supported placeholders', () => {
    expect(AI_DEDUP_PROMPT_VERSION).toBe('ai-dedup-prompt-v1.0');
    expect(promptVersion()).toBe(AI_DEDUP_PROMPT_VERSION);
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('{{asset_count}}');
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('{{keep_count}}');
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('{{strategy_hint}}');
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('【输出格式】');
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('【严格约束】');
    // v1.1: the reason bullet must require a concrete disadvantage, not vague wording.
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('相对本组最佳照片的');
    expect(AI_DEDUP_DEFAULT_PROMPT).toContain('禁止使用「这张更差」「评分较低」等空泛表述');
  });
});

describe('renderPrompt', () => {
  it('substitutes only the three exact placeholders', () => {
    const rendered = renderPrompt(AI_DEDUP_DEFAULT_PROMPT, {
      assetCount: 3,
      keepCount: 1,
      strategyHint: '  优先保留横构图  ',
    });
    expect(rendered).not.toContain('{{asset_count}}');
    expect(rendered).not.toContain('{{keep_count}}');
    expect(rendered).not.toContain('{{strategy_hint}}');
    expect(rendered).toContain('编号为 1 到 3');
    expect(rendered).toContain('保留的 1 张');
    expect(rendered).toContain('优先保留横构图');
  });

  it('leaves an empty strategy hint as an empty segment', () => {
    const rendered = renderPrompt(AI_DEDUP_DEFAULT_PROMPT, {
      assetCount: 2,
      keepCount: 1,
      strategyHint: '',
    });
    expect(rendered).toContain('【策略附加段】（由管理员在提示词中配置，为空则忽略本段）\n\n\n【严格约束】');
  });
});

describe('strategySummary / diffSummary', () => {
  it('returns the default label for an empty hint and truncates long hints', () => {
    expect(strategySummary('')).toBe('默认策略（清晰度 / 画质 / 构图）');
    expect(strategySummary(' '.repeat(3))).toBe('默认策略（清晰度 / 画质 / 构图）');
    const summary = strategySummary('策'.repeat(60));
    expect(summary.endsWith('…')).toBe(true);
    expect([...summary]).toHaveLength(41);
  });

  it('reports an identical template and a line-level difference otherwise', () => {
    expect(diffSummary(AI_DEDUP_DEFAULT_PROMPT)).toBe('与默认提示词一致');
    expect(diffSummary(`${AI_DEDUP_DEFAULT_PROMPT}\n新增一行`)).toContain('行新增');
  });
});
