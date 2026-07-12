-- AI監督フィードバック機能（docs/技術実装仕様書.md §20.5.4, §20.6）

-- 広告視聴チケット。create-ad-ticket で発行し、ad-reward-callback（AdMob SSV）が
-- verified=true に更新する。ai-coach-feedback はこのテーブルを見て生成を許可する。
CREATE TABLE ad_reward_tickets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    local_session_id TEXT NOT NULL,
    persona TEXT NOT NULL,
    verified BOOLEAN NOT NULL DEFAULT false,
    verified_at TIMESTAMPTZ,
    consumed_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE ad_reward_tickets ENABLE ROW LEVEL SECURITY;

-- 通常のクライアント操作は自分の行のみ。ad-reward-callback は Service Role Key で
-- 動作するため RLS をバイパスして verified を更新する。
CREATE POLICY "Users can read own ad tickets" ON ad_reward_tickets
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users can insert own ad tickets" ON ad_reward_tickets
    FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE INDEX idx_ad_reward_tickets_lookup
    ON ad_reward_tickets (id, user_id, verified, consumed_count, verified_at);

-- AI監督フィードバックの生成結果。§20.6の通り (session, persona) の組み合わせで
-- 複数バリエーション（再生成）を履歴として保持する。ticket_id が NULL の行は
-- fail-open（広告なし）経由での生成で、1日3回上限のカウント対象。
CREATE TABLE ai_coach_feedbacks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id),
    local_session_id TEXT NOT NULL,
    persona TEXT NOT NULL,
    ticket_id UUID REFERENCES ad_reward_tickets(id),
    positive TEXT NOT NULL,
    improvement TEXT NOT NULL,
    summary TEXT NOT NULL,
    persona_recognized BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE ai_coach_feedbacks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own ai coach feedbacks" ON ai_coach_feedbacks
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "Users can insert own ai coach feedbacks" ON ai_coach_feedbacks
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- 履歴チップ表示（session単位で新しい順）と、fail-open 1日3回上限のカウントの両方で使う
CREATE INDEX idx_ai_coach_feedbacks_session
    ON ai_coach_feedbacks (user_id, local_session_id, created_at DESC);
CREATE INDEX idx_ai_coach_feedbacks_failopen_count
    ON ai_coach_feedbacks (user_id, created_at)
    WHERE ticket_id IS NULL;
