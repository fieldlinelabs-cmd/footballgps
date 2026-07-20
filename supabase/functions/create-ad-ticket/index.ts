// docs/技術実装仕様書.md §20.5.1, §24
// 広告表示前に呼び、生成の「予約チケット」を発行する。
// purpose により複数機能（AI監督フィードバック・二つ名生成 等）でこのチケットシステムを
// 共用する。persona は purpose='coach_feedback' の場合のみ必須。

import { createAdminClient, resolveUser } from "../_shared/supabaseClients.ts";

interface RequestBody {
  localSessionId: string;
  persona?: string;
  purpose?: string;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), { status: 405 });
  }

  const user = await resolveUser(req.headers.get("Authorization"));
  if (!user) {
    return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_body" }), { status: 400 });
  }

  const localSessionId = body.localSessionId?.trim();
  const purpose = body.purpose?.trim() || "coach_feedback";
  const persona = body.persona?.trim() || null;

  if (!localSessionId) {
    return new Response(JSON.stringify({ error: "invalid_params" }), { status: 400 });
  }
  if (purpose === "coach_feedback" && (!persona || persona.length > 50)) {
    return new Response(JSON.stringify({ error: "invalid_params" }), { status: 400 });
  }

  const admin = createAdminClient();
  const { data, error } = await admin
    .from("ad_reward_tickets")
    .insert({
      user_id: user.id,
      local_session_id: localSessionId,
      persona,
      purpose,
    })
    .select("id")
    .single();

  if (error || !data) {
    console.error("create-ad-ticket insert failed", error);
    return new Response(JSON.stringify({ error: "insert_failed" }), { status: 500 });
  }

  return new Response(JSON.stringify({ ticketId: data.id }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
