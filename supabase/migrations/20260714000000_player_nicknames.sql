-- 二つ名生成機能（docs/技術実装仕様書.md §24）

-- ad_reward_tickets を複数機能で共用できるよう汎用化する。
-- persona は AI監督フィードバック（purpose='coach_feedback'）専用の情報のため、
-- 他機能（purpose='nickname' 等）では NULL のまま使う。
ALTER TABLE ad_reward_tickets ADD COLUMN purpose TEXT NOT NULL DEFAULT 'coach_feedback';
ALTER TABLE ad_reward_tickets ALTER COLUMN persona DROP NOT NULL;

-- 二つ名の生成結果。ai_coach_feedbacks と同型。
-- プレイヤーデータ画面のヘッダーには「セッションを問わず最新1件」を称号として表示する。
CREATE TABLE player_nicknames (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    local_session_id TEXT NOT NULL,
    ticket_id UUID REFERENCES ad_reward_tickets(id),
    nickname TEXT NOT NULL,
    reason TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE player_nicknames ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own nicknames" ON player_nicknames
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users can insert own nicknames" ON player_nicknames
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- ヘッダー表示用（セッション条件なしで最新1件を引く）
CREATE INDEX idx_player_nicknames_latest
    ON player_nicknames (user_id, created_at DESC);

-- fail-open 1日上限のカウント対象
CREATE INDEX idx_player_nicknames_failopen_count
    ON player_nicknames (user_id, created_at)
    WHERE ticket_id IS NULL;
