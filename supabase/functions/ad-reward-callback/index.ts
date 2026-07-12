// docs/技術実装仕様書.md §20.5.2
// AdMobリワード広告のServer-Side Verification (SSV) 受け口。
// AdMobダッシュボードでこのURLをSSVコールバックURLとして登録する。
// Googleのサーバーからのみ呼ばれる想定で、匿名認証JWTは付かない（署名検証で真正性を担保する）。
//
// AdMobは200が返らない場合、1秒間隔で最大5回再送する。custom_data（=ticketId）の
// verified更新は何度実行しても結果が同じなので、このハンドラは冪等。

import { createAdminClient } from "../_shared/supabaseClients.ts";
import { verifySsvCallback } from "../_shared/admobSsv.ts";

Deno.serve(async (req) => {
  const url = new URL(req.url);

  try {
    const { valid, customData } = await verifySsvCallback(url);

    if (!valid || !customData) {
      console.error("ad-reward-callback: signature verification failed", {
        query: url.search,
      });
      return new Response("ok", { status: 200 });
    }

    const admin = createAdminClient();
    const { error } = await admin
      .from("ad_reward_tickets")
      .update({ verified: true, verified_at: new Date().toISOString() })
      .eq("id", customData);

    if (error) {
      console.error("ad-reward-callback: failed to update ticket", error);
    }

    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("ad-reward-callback: unexpected error", e);
    // Google側の仕様: 200を返さないと最大5回再送されるため、内部エラーでも200で応答する
    return new Response("ok", { status: 200 });
  }
});
