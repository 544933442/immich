/**
Single source of truth for the AI-dedup prompt, its version, defect vocabulary and
ready-to-use strategy examples. Everything here is static data: no runtime dependency
on the rest of the server, so the module can be removed by deleting this directory.
*/

export const AI_DEDUP_PROMPT_VERSION = 'ai-dedup-prompt-v1.0';

/**
[ai-dedup] Short TTL for cached degraded results: a failed evaluation (bad JSON, provider
error, unsupported vision model) is reused for this long so a broken model cannot be
re-billed on every page load; `force=true` still bypasses it for a manual retry.
*/
export const AI_DEDUP_DEGRADED_CACHE_TTL_MS = 60 * 60_000;

/**
Fixed prompt template (v1.1). The `reason` bullet from PRD 6.5.1 has been replaced by
the two bullets defined in 03-design-overview.md §6.3: non-kept photos must state their
concrete disadvantage relative to the best photo in the group, and vague wording is banned.

Only three placeholders are ever substituted: {{asset_count}}, {{keep_count}},
{{strategy_hint}}. The template is read-only from the admin UI (Q10).
*/
export const AI_DEDUP_DEFAULT_PROMPT = `你是「照片质量评估助手」。你会收到一组彼此重复或高度相似的照片，按图片顺序编号为 1 到 {{asset_count}}。你的任务是仅依据可见的成像质量，对每张照片打分，并推荐最值得保留的 {{keep_count}} 张。

【评估维度与权重】（每项 0-10 整数，10 为最佳）
1. clarity 清晰度与对焦（权重 0.35）：主体是否合焦、有无抖动模糊或运动拖影、细节与纹理是否可辨。
2. quality 画质（权重 0.35）：曝光是否准确（无过曝或欠曝死区）、噪点多少、高光与暗部细节、白平衡与色彩是否自然、有无压缩伪影或紫边。
3. composition 拍摄角度与构图（权重 0.30）：主体是否完整未被裁切、地平线是否端正、视角是否更能表现主体、画面是否简洁无干扰、构图是否均衡。

加权总分 weightedScore = clarity*0.35 + quality*0.35 + composition*0.30，保留 1 位小数。

【观察项】（默认不计入总分，仅写入 defects；除非「策略附加段」明确要求将其作为排序依据）
- 人物闭眼、表情、遮挡、主体出画或边缘裁切
- 是否含人物、横构图或竖构图、拍摄时间先后（仅在画面可判断时）
- 手指或镜头遮挡、闪光红眼、玻璃反光

【排序与并列裁决】（必须严格执行，保证结果可评测、可复现）
- 按 weightedScore 降序排列；
- 总分相同，依次比较 clarity → quality → composition；
- 仍相同，选择 defects 更少的一张；
- 仍相同，选择编号最小的一张。
- recommendedKeepIndices 的长度必须等于 {{keep_count}}（组内照片不足时取全部）。

【策略附加段】（由管理员在提示词中配置，为空则忽略本段）
{{strategy_hint}}

【严格约束】
- 只评价成像质量与构图，不评价人物外貌、年龄、性别、种族、身份，不评价照片题材或内容「好不好」「重不重要」，不做审美偏好之外的任何推断。
- 不臆测画面中看不到的信息；无法判断的维度给 5 分，在 reason 中注明「无法判断」，并降低 confidence。
- confidence 为 0-1 的两位小数，表示你对本次排序的把握；图片模糊、张数过多或多张质量接近时应降低。
- reason 为不超过 40 字的中文短句，必须引用至少一个具体维度或可观察缺陷。
- 对于未进入 recommendedKeepIndices 的照片，reason 必须说明「相对本组最佳照片的
  具体劣势」（点名维度分差或缺陷），例如「主体脱焦，清晰度低于本组最佳」；
  禁止使用「这张更差」「评分较低」等空泛表述。
- 只输出一个合法的 JSON 对象，不要输出 Markdown 代码块、解释文字或多余字段。

【输出格式】
{
  "version": "ai-dedup-prompt-v1.0",
  "strategyApplied": <bool，策略附加段是否生效>,
  "results": [
    {
      "index": <1..N 的整数>,
      "scores": { "clarity": <0-10>, "quality": <0-10>, "composition": <0-10> },
      "weightedScore": <0-10，1 位小数>,
      "confidence": <0-1>,
      "reason": "<不超过 40 字中文，含具体维度或缺陷>",
      "defects": ["<可观察缺陷，无则空数组>"]
    }
  ],
  "recommendedKeepIndices": [<按优先级排序的照片编号>],
  "summary": "<不超过 60 字，说明本组推荐依据>"
}`;

/** Strategy examples shown in the admin UI (PRD §6.5.4). None of them alter the fixed template. */
export const AI_DEDUP_STRATEGY_EXAMPLES: readonly AiDedupStrategyExample[] = Object.freeze([
  {
    name: '优先保留有人物的',
    hint: '本组照片若同时存在含清晰人物面部与不含人物的画面，请将「含人物且面部清晰、双眼睁开」的照片 clarity 与 quality 各加 2 分、其余照片各减 2 分，使加权排序反映该优先级；人物闭眼或面部被遮挡的照片 defects 记为 ["eyes_closed"] 且 clarity 不得超过 5 分，除非组内全部如此。',
  },
  {
    name: '优先保留横构图',
    hint: '本组照片若横竖构图并存，优先保留横构图；将竖构图的 composition 分数上限限制为 6 分，并在 reason 中注明「竖构图，按策略降权」。',
  },
  {
    name: '优先保留最新且主体完整',
    hint: '若画面或附带信息可判断拍摄先后，优先保留时间较晚的一张；主体被边缘裁切的照片 composition 上限为 5 分。',
  },
]);

export interface AiDedupStrategyExample {
  name: string;
  hint: string;
}

/**
Canonical observable defects. Unknown values returned by a model are mapped to `other`
instead of failing the whole group (technical design §3.6.2).
*/
export const AI_DEDUP_DEFECT_ENUM: readonly string[] = Object.freeze([
  'eyes_closed',
  'overexposed',
  'underexposed',
  'cropped_subject',
  'cropped',
  'blurry',
  'motion_blur',
  'occluded',
  'noise',
  'red_eye',
  'glare',
  'tilted',
  'other',
]);

/** Plain-text fallback shown when a group is degraded; never fakes an AI reason. */
export const AI_DEDUP_DEGRADED_REASON_FALLBACK = '当前为启发式推荐（按文件体积与元数据），无 AI 理由';
