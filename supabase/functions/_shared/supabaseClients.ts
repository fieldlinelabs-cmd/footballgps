import { createClient } from "npm:@supabase/supabase-js@2";

// Supabase Edge Functionsのランタイムには SUPABASE_URL / SUPABASE_ANON_KEY /
// SUPABASE_SERVICE_ROLE_KEY が自動で環境変数として渡される。

/** RLSをバイパスする管理者クライアント。呼び出し元の user_id は手動でフィルタすること。 */
export function createAdminClient() {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );
}

/** リクエストのAuthorizationヘッダーをそのまま使うクライアント（RLS適用）。 */
export function createUserClient(authHeader: string | null) {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: authHeader ? { Authorization: authHeader } : {} },
      auth: { persistSession: false },
    }
  );
}

/** Authorizationヘッダーからユーザーを解決する。未認証なら null。 */
export async function resolveUser(authHeader: string | null) {
  if (!authHeader) return null;
  const client = createUserClient(authHeader);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) return null;
  return data.user;
}
