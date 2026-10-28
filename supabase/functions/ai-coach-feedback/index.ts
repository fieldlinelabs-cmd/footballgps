// docs/技術実装仕様書.md §20.5.3
// AI監督フィードバック本体。ticketの検証（広告経由）またはfail-open上限チェック
// （広告なし）を行った上でGeminiを呼び出す。

import { createAdminClient, resolveUser } from "../_shared/supabaseClients.ts";
import { SYSTEM_INSTRUCTION, RESPONSE_SCHEMA } from "../_shared/prompt.ts";
import { checkGlobalDailyAllowance, getFailOpenDailyLimit } from "../_shared/geminiRateLimit.ts";
import { extractUsage, thinkingConfig, type GeminiUsage } from "../_shared/geminiUsage.ts";

type AdminClient = ReturnType<typeof createAdminClient>;

interface RequestBody {
  ticketId: string | null;
  localSessionId: string;
  persona: string;
  position: string | null;
  sessionSummary: string;
}

interface GeminiResult {
  positive: string;
  improvement: string;
  summary: string;
  personaRecognized: boolean;
  // 二つ名（§24）も同じ呼び出しで生成する。欠けていてもフィードバック本体は返す
  nickname: string | null;
  nicknameReason: string | null;
}

const MAX_PERSONA_LENGTH = 50;
const MAX_POSITION_LENGTH = 30;
const MAX_SESSION_SUMMARY_LENGTH = 4000;
const TICKET_POLL_INTERVAL_MS = 500;
const TICKET_POLL_MAX_ATTEMPTS = 10; // 合計最大5秒
const TICKET_VALID_WINDOW_MS = 5 * 60 * 1000;
const TICKET_MAX_CONSUMPTIONS = 3;
const GEMINI_MODEL = "gemini-2.5-flash";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const user = await resolveUser(req.headers.get("Authorization"));
  if (!user) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const persona = body.persona?.trim();
  const sessionSummary = body.sessionSummary?.trim();
  const localSessionId = body.localSessionId?.trim();
  const ticketId = body.ticketId ?? null;
  const position = body.position?.trim() || null;

  if (!persona || persona.length > MAX_PERSONA_LENGTH) {
    return json({ error: "invalid_persona" }, 400);
  }
  if (!sessionSummary || sessionSummary.length > MAX_SESSION_SUMMARY_LENGTH) {
    return json({ error: "invalid_session_summary" }, 400);
  }
  if (!localSessionId) {
    return json({ error: "invalid_params" }, 400);
  }
  if (position && position.length > MAX_POSITION_LENGTH) {
    return json({ error: "invalid_position" }, 400);
  }

  const admin = createAdminClient();

  const globalAllowed = await checkGlobalDailyAllowance(admin);
  if (!globalAllowed) {
    return json({ error: "service_busy" }, 429);
  }

  if (ticketId) {
    const verifyResult = await waitForTicketVerification(admin, ticketId, user.id);
    if (!verifyResult.ok) {
      return json({ error: verifyResult.error }, 409);
    }
  } else {
    const allowed = await checkFailOpenAllowance(admin, user.id);
    if (!allowed) {
      return json({ error: "daily_limit_reached" }, 429);
    }
  }

  const geminiResult = await callGemini(persona, position, sessionSummary);
  if (!geminiResult.ok) {
    return json({ error: geminiResult.error }, geminiResult.status);
  }

  const { data: savedRow, error: insertError } = await admin
    .from("ai_coach_feedbacks")
    .insert({
      user_id: user.id,
      local_session_id: localSessionId,
      persona,
      position,
      ticket_id: ticketId,
      positive: geminiResult.data.positive,
      improvement: geminiResult.data.improvement,
      summary: geminiResult.data.summary,
      persona_recognized: geminiResult.data.personaRecognized,
      nickname: geminiResult.data.nickname,
      nickname_reason: geminiResult.data.nicknameReason,
      ...geminiResult.usage,
    })
    .select("id")
    .single();
  if (insertError) {
    console.error("ai-coach-feedback: failed to save result", insertError);
  }

  // プレイヤーデータ画面の称号表示（fetchLatestNickname）はplayer_nicknamesの最新行を読むため、
  // ここにも保存する。coach_feedback_idを付けることで、Geminiの呼び出し回数の集計や
  // ai-nicknameのfail-open上限で二重に数えないようにする
  if (savedRow && geminiResult.data.nickname && geminiResult.data.nicknameReason) {
    const { error: nicknameError } = await admin.from("player_nicknames").insert({
      user_id: user.id,
      local_session_id: localSessionId,
      ticket_id: ticketId,
      nickname: geminiResult.data.nickname,
      reason: geminiResult.data.nicknameReason,
      coach_feedback_id: savedRow.id,
    });
    if (nicknameError) {
      console.error("ai-coach-feedback: failed to save nickname", nicknameError);
    }
  }

  // 成功時のみticketを消費する。失敗時は消費しないことで無料リトライを実現する（§20.6）。
  if (ticketId) {
    const { data: ticketRow } = await admin
      .from("ad_reward_tickets")
      .select("consumed_count")
      .eq("id", ticketId)
      .single();
    if (ticketRow) {
      await admin
        .from("ad_reward_tickets")
        .update({ consumed_count: ticketRow.consumed_count + 1 })
        .eq("id", ticketId);
    }
  }

  return json(geminiResult.data, 200);
});

async function waitForTicketVerification(
  admin: AdminClient,
  ticketId: string,
  userId: string
): Promise<{ ok: true } | { ok: false; error: string }> {
  for (let attempt = 0; attempt < TICKET_POLL_MAX_ATTEMPTS; attempt++) {
    const { data, error } = await admin
      .from("ad_reward_tickets")
      .select("verified, verified_at, consumed_count, user_id, purpose")
      .eq("id", ticketId)
      .single();

    if (error || !data || data.user_id !== userId || data.purpose !== "coach_feedback") {
      return { ok: false, error: "invalid_ticket" };
    }
    if (data.consumed_count >= TICKET_MAX_CONSUMPTIONS) {
      return { ok: false, error: "ticket_exhausted" };
    }
    if (data.verified) {
      if (!data.verified_at) {
        return { ok: false, error: "invalid_ticket" };
      }
      const verifiedAt = new Date(data.verified_at).getTime();
      if (Date.now() - verifiedAt <= TICKET_VALID_WINDOW_MS) {
        return { ok: true };
      }
      return { ok: false, error: "ticket_expired" };
    }

    if (attempt < TICKET_POLL_MAX_ATTEMPTS - 1) {
      await sleep(TICKET_POLL_INTERVAL_MS);
    }
  }
  return { ok: false, error: "ticket_not_verified" };
}

async function checkFailOpenAllowance(admin: AdminClient, userId: string): Promise<boolean> {
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { count, error } = await admin
    .from("ai_coach_feedbacks")
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .is("ticket_id", null)
    .gte("created_at", since);

  if (error) {
    console.error("ai-coach-feedback: failed to count fail-open usage", error);
    // カウントできない場合は安全側に倒して拒否する
    return false;
  }
  return (count ?? 0) < getFailOpenDailyLimit();
}

async function callGemini(
  persona: string,
  position: string | null,
  sessionSummary: string
): Promise<
  { ok: true; data: GeminiResult; usage: GeminiUsage } | { ok: false; error: string; status: number }
> {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    console.error("ai-coach-feedback: GEMINI_API_KEY is not set");
    return { ok: false, error: "internal_error", status: 500 };
  }

  const positionTag = position ? `<position>${escapeForTag(position)}</position>` : "";
  const userContent =
    `<persona>${escapeForTag(persona)}</persona>${positionTag}\n` +
    `<session_data>${escapeForTag(sessionSummary)}</session_data>`;

  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

  let response: Response;
  try {
    response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
        contents: [{ parts: [{ text: userContent }] }],
        generationConfig: {
          temperature: 0.8,
          responseMimeType: "application/json",
          responseSchema: RESPONSE_SCHEMA,
          thinkingConfig: thinkingConfig(),
        },
      }),
    });
  } catch (e) {
    console.error("ai-coach-feedback: Gemini request failed", e);
    return { ok: false, error: "gemini_unreachable", status: 502 };
  }

  if (!response.ok) {
    const errorBody = await response.text();
    console.error("ai-coach-feedback: Gemini returned non-2xx", response.status, errorBody);
    if (response.status === 429) {
      // Gemini自体のレート制限に到達。こちらのグローバル上限チェックとは別に、
      // Google側の実際のクォータ超過として同じservice_busyエラーで扱う
      return { ok: false, error: "service_busy", status: 429 };
    }
    return { ok: false, error: "gemini_error", status: 502 };
  }

  const payload = await response.json();

  if (payload.promptFeedback?.blockReason) {
    return { ok: false, error: "content_blocked", status: 422 };
  }

  const text = payload.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string") {
    console.error("ai-coach-feedback: unexpected Gemini response shape", payload);
    return { ok: false, error: "gemini_error", status: 502 };
  }

  try {
    const parsed = JSON.parse(text);
    if (
      typeof parsed.positive !== "string" ||
      typeof parsed.improvement !== "string" ||
      typeof parsed.summary !== "string" ||
      typeof parsed.personaRecognized !== "boolean"
    ) {
      throw new Error("missing or invalid fields in Gemini JSON response");
    }
    const nickname = typeof parsed.nickname === "string" && parsed.nickname.trim() ? parsed.nickname.trim() : null;
    const nicknameReason =
      typeof parsed.nicknameReason === "string" && parsed.nicknameReason.trim() ? parsed.nicknameReason.trim() : null;
    return {
      ok: true,
      data: {
        positive: parsed.positive,
        improvement: parsed.improvement,
        summary: parsed.summary,
        personaRecognized: parsed.personaRecognized,
        nickname,
        nicknameReason,
      },
      usage: extractUsage(payload),
    };
  } catch (e) {
    console.error("ai-coach-feedback: failed to parse Gemini JSON", e, text);
    return { ok: false, error: "gemini_parse_error", status: 502 };
  }
}

function escapeForTag(value: string): string {
  return value.replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
