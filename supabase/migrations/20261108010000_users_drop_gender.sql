-- users.gender はサーバー側（関数・データベースの処理）のどこでも読んでいないため、送信をやめて列を削除する（2026-11-08）。
-- 表示名・生年月日を消したとき（20261029000000・20261029010000）と同じ考え方で、App Store のプライバシー表示を軽くする。
-- users に残るのは匿名のIDと作成日時だけ。AI機能のテーブル（ai_coach_feedbacks・ad_reward_tickets・player_nicknames）が
-- users(id) を参照しているため、行そのものは残す。詳細は docs/技術実装仕様書.md §14.2。

alter table public.users drop column if exists gender;
