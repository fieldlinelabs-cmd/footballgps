-- AI監督フィードバックの生成時に二つ名も同時に生成する（1回のGemini呼び出しで両方を返す）。
-- ai_coach_feedbacks: 履歴の再表示用に二つ名を保持する。
-- player_nicknames: プレイヤーデータ画面の称号表示用に同じ二つ名を保存し、どのフィードバックで
--   生成されたかをcoach_feedback_idで持つ（呼び出し回数の集計で二重に数えないため）。

alter table public.ai_coach_feedbacks
  add column nickname text,
  add column nickname_reason text;

alter table public.player_nicknames
  add column coach_feedback_id uuid references public.ai_coach_feedbacks(id) on delete set null;
