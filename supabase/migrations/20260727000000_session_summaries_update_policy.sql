-- session_summaries には SELECT/INSERT ポリシーしか存在せず、UPDATE ポリシーが無かったため、
-- upsert の ON CONFLICT DO UPDATE 経路が常に RLS で拒否されていた（新規行の初回 INSERT のみ成功する状態）。
-- 自分自身の行を UPDATE できるポリシーを追加する。
create policy "Users can update own sessions"
on public.session_summaries
for update
using (user_id = auth.uid())
with check (user_id = auth.uid());
