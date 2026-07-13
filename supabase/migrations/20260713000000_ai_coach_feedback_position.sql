-- AI監督フィードバック機能: ポジション入力の追加（docs/技術実装仕様書.md §20.3, §20.7）
-- ユーザーが任意で入力するポジション（例: ボランチ、サイドバック）を記録する。
-- 監督名と同様、生成のたびに入力する自由入力欄（未入力可）。

ALTER TABLE ai_coach_feedbacks
    ADD COLUMN position TEXT;
