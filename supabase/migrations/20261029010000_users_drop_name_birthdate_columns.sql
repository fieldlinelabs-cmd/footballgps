-- docs/技術実装仕様書.md §14.2
-- 表示名と生年月日はアプリから送らなくなり（20261029000000）、テスト端末も1台だけで
-- 古いビルドを考慮する必要がないため、列そのものを削除する（2026-10-29）。

alter table public.users drop column if exists display_name;
alter table public.users drop column if exists birth_date;
