-- docs/技術実装仕様書.md §14.2
-- 表示名と生年月日はサーバーで使っていないため、アプリから送るのをやめた（2026-10-29）。
-- 保存済みの値も消す。古いビルドのアプリが送ってきてもエラーにならないよう、列は残す。

update public.users
set display_name = '',
    birth_date = null
where display_name <> '' or birth_date is not null;
