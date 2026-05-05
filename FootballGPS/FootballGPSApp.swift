//
//  FootballGPSApp.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

@main
struct FootballGPSApp: App {
    
    init() {
        // WatchConnectivityサービスを初期化
        _ = PhoneWatchConnectivityService.shared
        
        // 🧪 開発用: シミュレーター向けにテストデータを追加
        #if targetEnvironment(simulator)
        addTestDataIfNeeded()
        #endif
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
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


