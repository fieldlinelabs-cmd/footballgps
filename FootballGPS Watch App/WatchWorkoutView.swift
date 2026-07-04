//
//  WorkoutView.swift
//  FootballGPS Watch App
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import WatchConnectivity

struct WorkoutView: View {
    @StateObject private var workoutManager = WorkoutManager()
    @State private var showingSummary = false
    
    var body: some View {
        ZStack {
            if !showingSummary {
                if workoutManager.isRunning {
                    // 記録中の画面
                    RunningView(workoutManager: workoutManager, showingSummary: $showingSummary)
                        .transition(.opacity)
                } else {
                    // 開始画面
                    StartView(workoutManager: workoutManager)
                        .transition(.opacity)
                }
            } else {
                // サマリー画面
                SummaryView(workoutManager: workoutManager, isPresented: $showingSummary)
                    .transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showingSummary)
        .animation(.easeInOut(duration: 0.3), value: workoutManager.isRunning)
    }
}

// MARK: - Start View

struct StartView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @State private var isRequestingPermission = false
    @State private var showError = false
    @State private var errorMessage = ""
    var body: some View {
        VStack(spacing: 15) {
            Image(systemName: "figure.run")
                .font(.system(size: 50))
                .foregroundStyle(.green)
            
            Text("Football GPS")
                .font(.headline)
            
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // 通常のワークアウト開始ボタン
            Button {
                Task {
                    isRequestingPermission = true
                    showError = false
                    do {
                        try await workoutManager.requestAuthorization()
                        try await workoutManager.startWorkout()
                    } catch {
                        print("❌ エラー: \(error)")
                        print("❌ エラー詳細: \(error.localizedDescription)")
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                    isRequestingPermission = false
                }
            } label: {
                if isRequestingPermission {
                    ProgressView()
                } else {
                    Label("開始", systemImage: "play.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequestingPermission)
            
        }
        .padding()
    }
}

// MARK: - Running View

struct RunningView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @Binding var showingSummary: Bool
    @State private var showingEndConfirmation = false
    @State private var showingGPSDebug = false
    @State private var showStartConfirmed = false

    var body: some View {
        // スクロール領域 (Digital Crown 対応)
        ScrollView {
            VStack(spacing: 10) {
                // GPS状態フィードバック（VStack最上部）
                if !workoutManager.startPointConfirmed {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("GPS安定中...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if showStartConfirmed {
                    Text("Start確定！")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.green)
                }

                // 経過時間
                Text(formatTime(workoutManager.elapsedTime))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                
                // 統計データ
                VStack(spacing: 8) {
                    StatRow(
                        label: "距離",
                        value: String(format: "%.0f m", workoutManager.distance),
                        icon: "figure.walk"
                    )
                    
                    StatRow(
                        label: "速度",
                        value: String(format: "%.1f m/s", workoutManager.currentSpeed),
                        icon: "speedometer"
                    )
                    
                    StatRow(
                        label: "最高速度",
                        value: String(format: "%.1f m/s", workoutManager.maxSpeed),
                        icon: "flame.fill"
                    )
                    
                    StatRow(
                        label: "GPS点",
                        value: "\(workoutManager.gpsPoints.count)",
                        icon: "location.fill"
                    )

                    StatRow(
                        label: "心拍",
                        value: workoutManager.heartRate > 0
                            ? String(format: "%.0f bpm", workoutManager.heartRate)
                            : "-- bpm",
                        icon: "heart.fill"
                    )

                    StatRow(
                        label: "消費",
                        value: workoutManager.activeCalories > 0
                            ? String(format: "%.0f kcal", workoutManager.activeCalories)
                            : "-- kcal",
                        icon: "flame.fill"
                    )
                }
                .font(.caption)
                
                // GPSデバッグボタン
                Button {
                    showingGPSDebug = true
                } label: {
                    Text("GPS詳細")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
            .padding()
        }
        // コントロールボタンを画面下部に固定 (小型モデルでの見切れ防止)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 20) {
                // 一時停止/再開
                Button {
                    if workoutManager.isPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                } label: {
                    Image(systemName: workoutManager.isPaused ? "play.fill" : "pause.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .tint(workoutManager.isPaused ? .green : .orange)
                
                // 終了
                Button {
                    showingEndConfirmation = true
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title2)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.black.opacity(0.8))
        }
        .alert("ワークアウトを終了しますか？", isPresented: $showingEndConfirmation) {
            Button("キャンセル", role: .cancel) {}
            Button("終了", role: .destructive) {
                Task {
                    do {
                        try await workoutManager.endWorkout()
                        showingSummary = true
                    } catch {
                        print("❌ 終了エラー: \(error)")
                    }
                }
            }
        }
        .sheet(isPresented: $showingGPSDebug) {
            GPSDebugView(gpsPoints: workoutManager.gpsPoints)
        }
        .onChange(of: workoutManager.startPointConfirmed) { _, confirmed in
            if confirmed {
                showStartConfirmed = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    showStartConfirmed = false
                }
            }
        }
    }

    private func formatTime(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 20)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Summary View

struct SummaryView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @Binding var isPresented: Bool
    @StateObject private var connectivityService = WatchConnectivityService.shared
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // ✅と完了！を横並び
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.green)

                    Text("完了！")
                        .font(.title3)
                        .fontWeight(.bold)
                }

                // 統計データ（コンパクト）
                VStack(alignment: .leading, spacing: 4) {
                    SummaryRow(label: "時間", value: formatDuration(workoutManager.elapsedTime))
                    SummaryRow(label: "距離", value: String(format: "%.0f m", workoutManager.distance))
                    SummaryRow(label: "平均", value: String(format: "%.1f m/s", workoutManager.distance / max(workoutManager.elapsedTime, 1)))
                    SummaryRow(label: "最高", value: String(format: "%.1f m/s", workoutManager.maxSpeed))
                    SummaryRow(label: "GPS", value: "\(workoutManager.gpsPoints.count)点")
                    SummaryRow(label: "心拍数", value: workoutManager.heartRate > 0
                        ? String(format: "%.0f bpm", workoutManager.heartRate) : "--")
                    SummaryRow(label: "カロリー", value: workoutManager.activeCalories > 0
                        ? String(format: "%.0f kcal", workoutManager.activeCalories) : "--")
                    SummaryRow(label: "最大加速度", value: workoutManager.peakAcceleration > 0
                        ? String(format: "%.2f G", workoutManager.peakAcceleration) : "--")
                }
                .font(.caption)
                .padding(8)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)

                // 送信状態（コンパクト）
                HStack(spacing: 4) {
                    Image(systemName: "applewatch")
                        .font(.caption2)
                        .foregroundStyle(connectivityService.isReachable ? .green : .orange)

                    if connectivityService.pendingTransferCount > 0 {
                        Text("送信待ち")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("iPhoneで確認")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // 完了ボタン
                Button {
                    workoutManager.isRunning = false
                    workoutManager.reset()
                    isPresented = false
                } label: {
                    Text("完了")
                        .font(.body)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .transition(.move(edge: .bottom))
    }
    
    private func formatDuration(_ timeInterval: TimeInterval) -> String {
        let hours = Int(timeInterval) / 3600
        let minutes = Int(timeInterval) / 60 % 60
        let seconds = Int(timeInterval) % 60
        
        if hours > 0 {
            return "\(hours)時間\(minutes)分"
        } else if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Test Data Send View

struct TestDataSendView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @Environment(\.dismiss) var dismiss
    @State private var sendingData = false
    @State private var sendResult = ""
    
    var body: some View {
        VStack(spacing: 20) {
            Text("テストデータ送信")
                .font(.headline)
            
            Text("iPhoneにテストデータを送信します")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            if !sendResult.isEmpty {
                Text(sendResult)
                    .font(.caption)
                    .foregroundStyle(sendResult.contains("成功") ? .green : .orange)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            
            Button {
                Task {
                    await sendTestData()
                }
            } label: {
                if sendingData {
                    ProgressView()
                } else {
                    Label("送信", systemImage: "paperplane.fill")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendingData)
            
            Button("閉じる") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
    
    private func sendTestData() async {
        sendingData = true
        sendResult = ""
        
        // テストデータを生成
        let testSession = TrainingSession(
            userId: "test_user",
            name: "テスト送信 - \(Date().formatted(date: .omitted, time: .shortened))",
            date: Date(),
            duration: 600, // 10分
            totalDistance: 850.0,
            maxSpeed: 6.5,
            avgSpeed: 1.42
        )
        
        // テスト用のGPSポイントを生成
        var testPoints: [GPSPoint] = []
        let baseLat = 35.681236
        let baseLon = 139.767125
        
        for i in 0..<30 {
            let point = GPSPoint(
                timestamp: Date().addingTimeInterval(Double(i) * 2),
                latitude: baseLat + Double.random(in: -0.001...0.001),
                longitude: baseLon + Double.random(in: -0.001...0.001),
                speed: Double.random(in: 0...7),
                altitude: 10,
                horizontalAccuracy: 10
            )
            testPoints.append(point)
        }
        
        let testGPSData = GPSData(sessionId: testSession.id, points: testPoints)
        
        // WatchConnectivityで送信
        let connectivityService = WatchConnectivityService.shared
        
        print("📤 テストデータ送信開始...")
        print("   - セッション: \(testSession.name)")
        print("   - GPSポイント数: \(testPoints.count)")
        
        // 送信実行
        connectivityService.sendSession(testSession, gpsData: testGPSData)
        
        // 結果を待つ
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2秒待機
        
        if WCSession.default.activationState == .activated {
            if WCSession.default.isReachable {
                sendResult = "✅ 送信成功!\niPhoneで確認してください"
            } else {
                sendResult = "📦 キューに追加\n後で自動送信されます"
            }
        } else {
            sendResult = "⚠️ WatchConnectivity未初期化\nもう一度試してください"
        }
        
        sendingData = false
    }
}

#Preview {
    WorkoutView()
}
// MARK: - GPS Debug View

struct GPSDebugView: View {
    let gpsPoints: [GPSPoint]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("総GPS点数: \(gpsPoints.count)")
                        .font(.headline)
                } header: {
                    Text("統計")
                }
                
                Section {
                    ForEach(Array(gpsPoints.enumerated().reversed().prefix(20)), id: \.offset) { index, point in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("点 #\(gpsPoints.count - index)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("緯度: \(String(format: "%.6f", point.latitude))")
                                        .font(.caption2)
                                    Text("経度: \(String(format: "%.6f", point.longitude))")
                                        .font(.caption2)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("速度: \(String(format: "%.1f", point.speed)) m/s")
                                        .font(.caption2)
                                    Text("精度: \(String(format: "%.1f", point.horizontalAccuracy))m")
                                        .font(.caption2)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("最新20点")
                }
                
                if gpsPoints.isEmpty {
                    Section {
                        Text("GPSポイントがまだ記録されていません")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("GPS詳細")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
    }
}

