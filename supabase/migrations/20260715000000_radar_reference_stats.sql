-- レーダーチャートのMax基準値を検討するための集計RPC（§24 開発者用デバッグ画面から利用）
-- session_summaries に蓄積された実績データから、軸ごとの分布（p50/p75/p90）を返す。
-- 現在のMax定数（SessionDataManager.computePlayerRadar）は据え置きのまま、
-- 開発者がこの集計を見て手動で定数を見直すための参考値であり、アプリが自動反映するものではない。
-- stamina軸はMax基準を持たない（stamina_drop自体が0〜1の絶対値のため対象外）。
create or replace function public.get_radar_reference_stats()
returns table (
  n bigint,
  distance_per_min_p50 double precision,
  distance_per_min_p75 double precision,
  distance_per_min_p90 double precision,
  sprint_per_min_p50 double precision,
  sprint_per_min_p75 double precision,
  sprint_per_min_p90 double precision,
  agility_per_min_p50 double precision,
  agility_per_min_p75 double precision,
  agility_per_min_p90 double precision,
  hr_intensity_ratio_p50 double precision,
  hr_intensity_ratio_p75 double precision,
  hr_intensity_ratio_p90 double precision,
  max_speed_ms_p50 double precision,
  max_speed_ms_p75 double precision,
  max_speed_ms_p90 double precision
)
language sql
security definer
set search_path = public
as $$
  select
    count(*) as n,
    percentile_cont(0.5) within group (order by total_distance_meters / (duration_seconds / 60.0)) as distance_per_min_p50,
    percentile_cont(0.75) within group (order by total_distance_meters / (duration_seconds / 60.0)) as distance_per_min_p75,
    percentile_cont(0.9) within group (order by total_distance_meters / (duration_seconds / 60.0)) as distance_per_min_p90,
    percentile_cont(0.5) within group (order by coalesce(sprint_count, 0) / (duration_seconds / 60.0)) as sprint_per_min_p50,
    percentile_cont(0.75) within group (order by coalesce(sprint_count, 0) / (duration_seconds / 60.0)) as sprint_per_min_p75,
    percentile_cont(0.9) within group (order by coalesce(sprint_count, 0) / (duration_seconds / 60.0)) as sprint_per_min_p90,
    percentile_cont(0.5) within group (order by agility_event_count / (duration_seconds / 60.0)) filter (where agility_event_count is not null) as agility_per_min_p50,
    percentile_cont(0.75) within group (order by agility_event_count / (duration_seconds / 60.0)) filter (where agility_event_count is not null) as agility_per_min_p75,
    percentile_cont(0.9) within group (order by agility_event_count / (duration_seconds / 60.0)) filter (where agility_event_count is not null) as agility_per_min_p90,
    percentile_cont(0.5) within group (order by hr_intensity_ratio) filter (where hr_intensity_ratio is not null) as hr_intensity_ratio_p50,
    percentile_cont(0.75) within group (order by hr_intensity_ratio) filter (where hr_intensity_ratio is not null) as hr_intensity_ratio_p75,
    percentile_cont(0.9) within group (order by hr_intensity_ratio) filter (where hr_intensity_ratio is not null) as hr_intensity_ratio_p90,
    percentile_cont(0.5) within group (order by max_speed_ms) as max_speed_ms_p50,
    percentile_cont(0.75) within group (order by max_speed_ms) as max_speed_ms_p75,
    percentile_cont(0.9) within group (order by max_speed_ms) as max_speed_ms_p90
  from public.session_summaries
  where duration_seconds >= 300;
$$;

grant execute on function public.get_radar_reference_stats() to anon, authenticated;
