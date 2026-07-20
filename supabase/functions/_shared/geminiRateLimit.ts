// docs/技術実装仕様書.md §20.6
// ai-coach-feedback・ai-nicknameは同一のGEMINI_API_KEYを共有しており、
// Geminiのレート制限（RPM/RPD）はプロジェクト単位でかかる。
// ユーザー単位の上限だけではテスター数に比例して合計呼び出し数が増えてしまうため、
// 両機能・両経路（広告視聴経由 + fail-open）を合算したプロジェクト全体の1日上限で保護する。

import { createAdminClient } from "./supabaseClients.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

// 2026-07-18実測: Gemini 2.5 FlashのFree Tier上限はプロジェクト・モデル単位で1日20回
// （エラーレスポンスの quotaId: GenerateRequestsPerDayPerProjectPerModel-FreeTier, limit: 20 で確認）。
// 失敗した呼び出し（429以外のエラー）もクォータを消費しうるため、20よりかなり低い値に設定する。
const DEFAULT_GLOBAL_DAILY_LIMIT = 15;
const DEFAULT_FAIL_OPEN_DAILY_LIMIT = 2;

/** プロジェクト全体で直近24時間のGemini呼び出し合計が上限未満かどうかを返す。 */
export async function checkGlobalDailyAllowance(admin: AdminClient): Promise<boolean> {
  const limit = Number(Deno.env.get("GEMINI_GLOBAL_DAILY_LIMIT") ?? String(DEFAULT_GLOBAL_DAILY_LIMIT));
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const [feedbacks, nicknames] = await Promise.all([
    admin.from("ai_coach_feedbacks").select("id", { count: "exact", head: true }).gte("created_at", since),
    admin.from("player_nicknames").select("id", { count: "exact", head: true }).gte("created_at", since),
  ]);

  if (feedbacks.error || nicknames.error) {
    console.error("checkGlobalDailyAllowance: count query failed", feedbacks.error, nicknames.error);
    // カウントできない場合は安全側に倒して拒否する
    return false;
  }

  return (feedbacks.count ?? 0) + (nicknames.count ?? 0) < limit;
}

/** ユーザー単位のfail-open（広告なし）生成の1日上限。Supabase Secretsで上書き可能。 */
export function getFailOpenDailyLimit(): number {
  return Number(Deno.env.get("FAIL_OPEN_DAILY_LIMIT") ?? String(DEFAULT_FAIL_OPEN_DAILY_LIMIT));
}
