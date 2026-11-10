//
//  FootballGPSApp.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import GoogleMobileAds

@main
struct FootballGPSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // WatchConnectivityサービスを初期化
        _ = PhoneWatchConnectivityService.shared

        // 13歳未満と分かっている利用者の広告に子ども向けのタグを付ける。最初の広告の要求より前に設定する（広告仕様書 §10.3）
        AdConfiguration.applyAudienceSettings()

        // 広告SDKの初期化
        GADMobileAds.sharedInstance().start(completionHandler: nil)

        // 配布元（App Store・TestFlight・Xcode）を判定し、本番とテストのどちらの広告を使うか決める（広告仕様書 §10.2）
        Task { await AdConfiguration.resolveEnvironment() }

        // 🧪 実機でテスト広告を受け取るためのテストデバイス登録（シミュレーターは登録不要、
        // 標準で常にテストモード）。初回の広告リクエスト時にXcodeコンソールへ実機のデバイスIDが
        // 出力されるので、実機でテストしたくなったらそのIDをここに追加する。
        #if DEBUG
        GADMobileAds.sharedInstance().requestConfiguration.testDeviceIdentifiers = [
            // "ここにXcodeコンソールに出力された実機のデバイスIDを追加",
        ]
        #endif

        // 🧪 開発用: シミュレーター向けにテストデータを追加
        #if targetEnvironment(simulator)
        addTestDataIfNeeded()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    // Supabase の匿名ログインは起動時にはせず、AI機能を使うときにする（技術実装仕様書 §14.2）
                    // 推移グラフ用に、欠けている派生メトリクス・ポジションを一括計算する（統計推移仕様書 §7）
                    await SessionDataManager.shared.backfillDerivedMetrics()
                }
        }
        // 前面にいるうちに13歳の誕生日をまたいだ場合も、子ども向けのタグを外す（広告仕様書 §10.3）
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { AdConfiguration.applyAudienceSettings() }
        }
    }
    
    // 🧪 テストデータを追加（初回のみ）
    private func addTestDataIfNeeded() {
        let dataManager = SessionDataManager.shared
        
        // 既にデータがある場合はスキップ
        guard dataManager.sessions.isEmpty else {
            print("📂 既存データあり: テストデータの追加をスキップ")
            return
        }
        
        print("🧪 テストデータを追加します...")
        
        // テストセッション1（今日）
        let session1 = TrainingSession(
            id: "test_session_1",
            userId: "test_user",
            name: "午後練習",
            date: Date(),
            duration: 3600, // 1時間
            totalDistance: 5400,
            maxSpeed: 7.2,
            avgSpeed: 1.5
        )
        let gpsData1 = MockData.generateMockGPSData(sessionId: session1.id, pointCount: 300)
        dataManager.saveSession(session1, gpsData: gpsData1)
        
        // テストセッション2（昨日）
        let session2 = TrainingSession(
            id: "test_session_2",
            userId: "test_user",
            name: "朝練",
            date: Date().addingTimeInterval(-86400), // 1日前
            duration: 2700, // 45分
            totalDistance: 4200,
            maxSpeed: 6.8,
            avgSpeed: 1.56
        )
        let gpsData2 = MockData.generateMockGPSData(sessionId: session2.id, pointCount: 250)
        dataManager.saveSession(session2, gpsData: gpsData2)
        
        // テストセッション3（3日前）
        let session3 = TrainingSession(
            id: "test_session_3",
            userId: "test_user",
            name: "2026/01/05 14:30",
            date: Date().addingTimeInterval(-259200), // 3日前
            duration: 5400, // 1.5時間
            totalDistance: 7800,
            maxSpeed: 8.1,
            avgSpeed: 1.44
        )
        let gpsData3 = MockData.generateMockGPSData(sessionId: session3.id, pointCount: 400)
        dataManager.saveSession(session3, gpsData: gpsData3)
        
        print("✅ テストデータ追加完了: \(dataManager.sessions.count)件")
    }
}


