-- Gemini呼び出しごとのトークン消費量（usageMetadata）を記録し、1回あたりコストを実測できるようにする。
-- 既存行はNULL（記録開始前）。

alter table public.ai_coach_feedbacks
  add column prompt_tokens integer,
  add column output_tokens integer,
  add column thinking_tokens integer;

alter table public.player_nicknames
  add column prompt_tokens integer,
  add column output_tokens integer,
  add column thinking_tokens integer;
