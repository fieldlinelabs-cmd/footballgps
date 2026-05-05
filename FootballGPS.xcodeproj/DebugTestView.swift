//
//  DebugTestView.swift
//  FootballGPS
//
//  Created on 2026/03/01.
//

import SwiftUI
import CoreLocation

/// シミュレーター用のデバッグ・テストビュー
struct DebugTestView: View {
    @StateObject private var dataManager = SessionDataManager.shared
    @StateObject private var fieldManager = FieldManager.shared
    @State private var showingSessionDetail = false
    @State private var selectedSession: (TrainingSession, GPSData, Field)?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("シミュレーターでアプリの機能をテストできます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("デバッグモード")
                }
                
                Section {
                    Button {
                        generateMockSession(duration: 900) // 15分
                    } label: {
                        Label("15分のトレーニングを生成", systemImage: "plus.circle.fill")
                    }
                    
                    Button {
                        generateMockSession(duration: 1800) // 30分
                    } label: {
                        Label("30分のトレーニングを生成", systemImage: "plus.circle.fill")
                    }
                    
                    Button {
                        generateMockSession(duration: 3600) // 60分
                    } label: {
                        Label("60分のトレーニングを生成", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("モックデータ生成")
                }
                
                Section {
                    Button {
                        createTestField()
                    } label: {
                        Label("テストフィールドを作成", systemImage: "map.fill")
                    }
                    
                    if !fieldManager.fields.isEmpty {
                        Text("登録済み: \(fieldManager.fields.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("フィールド管理")
                }
                
                Section {
                    if !dataManager.sessions.isEmpty {
                        ForEach(dataManager.sessions.prefix(5)) { session in
                            Button {
                                showSessionDetail(session)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(session.name)
                                        .font(.headline)
                                    
                                    HStack {
                                        Text(formatDuration(session.duration))
                                        Text("•")
                                        Text(formatDistance(session.totalDistance))
                                        Text("•")
                                        Text("\(String(format: "%.1f", session.maxSpeed)) m/s")
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text("セッションがありません")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                } header: {
                    HStack {
                        Text("生成済みセッション")
                        Spacer()
                        if !dataManager.sessions.isEmpty {
                            Button("全削除") {
                                dataManager.clearAllData()
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
                
                Section {
                    Button(role: .destructive) {
                        dataManager.clearAllData()
                        fieldManager.clearAllFields()
                    } label: {
                        Label("すべてのデータをクリア", systemImage: "trash.fill")
                    }
                } header: {
                    Text("データ管理")
                }
            }
            .navigationTitle("デバッグテスト")
            .sheet(isPresented: $showingSessionDetail) {
                if let (session, gpsData, field) = selectedSession {
                    NavigationStack {
                        SessionDetailView(
                            session: session,
                            gpsData: gpsData,
                            field: field
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("閉じる") {
                                    showingSessionDetail = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func generateMockSession(duration: TimeInterval) {
        // フィールドが存在しない場合は作成
        if fieldManager.fields.isEmpty {
            createTestField()
        }
        
        guard let field = fieldManager.fields.first else {
            print("❌ フィールドがありません")
            return
        }
        
        // モックデータ生成
        let sessionId = UUID().uuidString
        let gpsData = MockDataGenerator.generateRealisticTrainingData(
            sessionId: sessionId,
            duration: duration,
            field: field
        )
        
        // 統計計算
        var totalDistance = 0.0
        var maxSpeed = 0.0
        
        for i in 1..<gpsData.points.count {
            let prev = gpsData.points[i - 1]
            let curr = gpsData.points[i]
            
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
            
            totalDistance += prevLoc.distance(from: currLoc)
            maxSpeed = max(maxSpeed, curr.speed)
        }
        
        let avgSpeed = totalDistance / duration
        
        var session = TrainingSession(
            id: sessionId,
            userId: "test_user",
            name: "モック \(Int(duration / 60))分 - \(formattedDate())",
            date: Date(),
            duration: duration,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed
        )
        
        // フィールドを自動設定
        session.fieldId = field.id
        
        // 保存
        dataManager.saveSession(session, gpsData: gpsData)
        
        print("✅ モックセッション生成完了: \(session.name)")
        print("📊 距離: \(String(format: "%.0f", totalDistance))m, 最高速度: \(String(format: "%.1f", maxSpeed))m/s")
    }
    
    private func createTestField() {
        let field = MockDataGenerator.generateTestField()
        fieldManager.addField(field)
        fieldManager.selectField(field.id)
        print("✅ テストフィールド作成: \(field.name)")
    }
    
    private func showSessionDetail(_ session: TrainingSession) {
        guard let gpsData = dataManager.getGPSData(for: session.id),
              let fieldId = session.fieldId,
              let field = fieldManager.getField(by: fieldId) else {
            print("❌ セッション詳細の取得に失敗")
            return
        }
        
        selectedSession = (session, gpsData, field)
        showingSessionDetail = true
    }
    
    // MARK: - Formatters
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        return "\(minutes)分"
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
    
    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

#Preview {
    DebugTestView()
}
