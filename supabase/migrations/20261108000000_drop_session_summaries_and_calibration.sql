-- セッション要約とキャリブレーションの送信をやめたため、テーブルと集計用の関数を削除する（2026-11-08）。
-- session_summaries を読んでいたのはレーダーの満点を決めるための開発者用の集計だけで、レーダーの満点を
-- 世界トップの記録に変えたため不要になった。calibration_results はスプリントの基準を実測から決めるための
-- もので、基準を研究・記録から決め直したため不要になった（開発用ビルドの手動送信だけで、公開版は送っていない）。
-- 詳細は docs/技術実装仕様書.md §14.2・§13.4・§17.2。将来の比較機能は、作るときに集め方をあらためて決める。

drop function if exists public.get_radar_reference_stats();
drop function if exists public.get_calibration_stats();

drop table if exists public.session_summaries;
drop table if exists public.calibration_results;
