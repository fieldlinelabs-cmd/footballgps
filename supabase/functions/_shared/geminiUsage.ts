// Gemini呼び出しのコスト制御とトークン消費量の記録（ai-coach-feedback・ai-nickname共通）。
//
// gemini-2.5-flashは既定で思考（thinking）が有効で、思考トークンは出力単価で課金される。
// JSON整形済みの短い文章生成には不要と判断し、既定では無効化する。
// 品質が落ちた場合はSupabase SecretsのGEMINI_THINKING_BUDGETで再デプロイなしに戻せる
// （-1: モデルに任せる動的思考、正の値: 思考トークン上限）。

const DEFAULT_THINKING_BUDGET = 0;

export function thinkingConfig(): { thinkingBudget: number } {
  const raw = Deno.env.get("GEMINI_THINKING_BUDGET");
  const budget = raw === undefined ? DEFAULT_THINKING_BUDGET : Number(raw);
  return { thinkingBudget: Number.isFinite(budget) ? budget : DEFAULT_THINKING_BUDGET };
}

export interface GeminiUsage {
  prompt_tokens: number | null;
  output_tokens: number | null;
  thinking_tokens: number | null;
}

// generateContentレスポンスのusageMetadataを、保存用の列名に変換する。
export function extractUsage(payload: unknown): GeminiUsage {
  // deno-lint-ignore no-explicit-any
  const meta = (payload as any)?.usageMetadata ?? {};
  const num = (v: unknown) => (typeof v === "number" ? v : null);
  const promptTokens = num(meta.promptTokenCount);
  return {
    prompt_tokens: promptTokens,
    output_tokens: num(meta.candidatesTokenCount),
    // 思考が無効だとthoughtsTokenCount自体が省略されるため、usageMetadataがあれば0扱い
    thinking_tokens: num(meta.thoughtsTokenCount) ?? (promptTokens === null ? null : 0),
  };
}
