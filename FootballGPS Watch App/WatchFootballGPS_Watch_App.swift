//
//  FootballGPS_Watch_App.swift
//  FootballGPS Watch App
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

@main
struct FootballGPS_Watch_App: App {
    
    init() {
        // WatchConnectivityサービスを初期化（同期的に実行）
        Task { @MainActor in
            _ = WatchConnectivityService.shared
            print("🔄 WatchConnectivityService初期化開始")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            WorkoutView()
        }
    }
}
