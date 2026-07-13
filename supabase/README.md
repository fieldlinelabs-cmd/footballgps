# AI監督フィードバック機能 — Supabaseデプロイ手順

`docs/技術実装仕様書.md` §20 の実装。以下はコードのデプロイに必要な手順（要Supabaseアカウント認証のため、ユーザー側で実行）。

## 1. CLIのログインとプロジェクトのリンク

```sh
supabase login
supabase link --project-ref cpbczeugekezejumretu
```

`cpbczeugekezejumretu` は `FootballGPS/Info.plist` の `SUPABASE_URL`
(`https://cpbczeugekezejumretu.supabase.co`) から取得した既存プロジェクトのref。

## 2. DBマイグレーション適用

```sh
supabase db push
```

`migrations/20260712000000_ai_coach_feedback.sql` が `ai_coach_feedbacks` と
`ad_reward_tickets` の2テーブル（RLS込み）を作成する。既存の `users` テーブル
（§14.2）への外部キー参照があるため、`users` テーブルが先に存在している必要がある
（既にデプロイ済みのはず）。

## 3. Gemini APIキーをSecretsに登録

```sh
supabase secrets set GEMINI_API_KEY=<Gemini APIキー>
```

Google AI Studio (https://aistudio.google.com/apikey) で発行したキーを使う。

## 4. Edge Functionsのデプロイ

```sh
supabase functions deploy create-ad-ticket
supabase functions deploy ad-reward-callback --no-verify-jwt
supabase functions deploy ai-coach-feedback
```

`ad-reward-callback` はAdMobのサーバーから匿名認証JWTなしで直接呼ばれるため、
`--no-verify-jwt` でSupabase側のJWT検証を無効化する（署名検証は関数内部で
AdMobのECDSA署名を使って別途行っている。§20.5.2参照）。

デプロイ後のURLは:

```
https://cpbczeugekezejumretu.supabase.co/functions/v1/create-ad-ticket
https://cpbczeugekezejumretu.supabase.co/functions/v1/ad-reward-callback
https://cpbczeugekezejumretu.supabase.co/functions/v1/ai-coach-feedback
```

## 5. AdMob側の設定（ダッシュボード操作・API無し）

1. AdMobでリワード広告ユニットを作成
2. 広告ユニット設定画面で「Server-side verification」のコールバックURLに
   `https://cpbczeugekezejumretu.supabase.co/functions/v1/ad-reward-callback`
   を登録
3. 発行された本番のApp ID・広告ユニットIDを控える

## 6. iOS側のプレースホルダーを本番IDに差し替え（完了・2026-07-13）

AdMobで実際のApp ID・広告ユニットIDを発行し、コードに反映済み。

| 項目 | 値 |
|---|---|
| `FootballGPS/Info.plist` の `GADApplicationIdentifier` | `ca-app-pub-4525766212952142~7564036498` |
| `FootballGPS/RewardedAdManager.swift` の `adUnitID` | `ca-app-pub-4525766212952142/9279453167` |
| SSVコールバックURL | `https://cpbczeugekezejumretu.supabase.co/functions/v1/ad-reward-callback`（AdMob側で確認・適用済み） |

## 7. 実機（TestFlight）での動作確認結果（2026-07-13）

- アプリがApp Storeにリンクされていないため、本番広告ユニットは実配信がほぼ無い状態（no-fill）。
  この場合は§20.6のfail-openが働き、広告なしで分析が生成される。これは想定通りの挙動
- Google公式のテスト広告ユニットID（`ca-app-pub-3940256099942544/1712485313`）に一時切り替えて
  検証したところ、広告の読み込み・表示・視聴完了コールバックは正常に動作することを確認。
  ただしテストIDはAdMobアカウントに紐付いていないためSSV通知が届かず、`ticket_not_verified`
  エラーになる（想定通り。テストID使用時はfail-openも発動しないため、分析生成そのものは失敗する）
- 上記の理由により、**iOS側は本番IDのままにしている**（fail-open任せで分析は生成できるため）
- アプリがApp Storeにリンクされ広告配信が承認されてから、本番広告ユニットでのSSV検証を
  改めて確認すること

## 8. fail-open上限の一時緩和（2026-07-13）

TestFlightでのソロテスト期間中、本番広告がno-fillし続けるため、fail-openの1日上限を
3回→**30回**に緩和した（`supabase/functions/ai-coach-feedback/index.ts` の
`FAIL_OPEN_DAILY_LIMIT`）。**この変更を反映するには再デプロイが必要:**

```sh
supabase functions deploy ai-coach-feedback
```

アプリがApp Storeにリンクされ広告配信が承認され、本番広告での生成が主流になったら
`FAIL_OPEN_DAILY_LIMIT` を3程度に戻すこと。

## 検証

- ローカルでの型チェック: `deno check --no-lock supabase/functions/*/index.ts`（要 `brew install deno`）
- デプロイ後は `docs/技術実装仕様書.md` §20.4 と同様の手順で、実際にiOSアプリから
  監督名を変えて生成し、`personaRecognized` の挙動やSSV検証が通ることを確認する
