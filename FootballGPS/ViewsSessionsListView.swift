//
//  SessionsListView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import Combine

struct SessionsListView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @ObservedObject private var connectivityService = PhoneWatchConnectivityService.shared
    
    var body: some View {
        NavigationStack {
            Group {
                if dataManager.sessions.isEmpty {
                    emptyStateView
                } else {
                    sessionsList
                }
            }
            .navigationTitle("マイセッション")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // 接続状態を表示
                        print("🔄 接続状態: \(connectivityService.isPaired ? "ペアリング済み" : "未ペアリング")")
                    } label: {
                        Image(systemName: connectivityService.isPaired ? "applewatch" : "applewatch.slash")
                            .foregroundStyle(connectivityService.isPaired ? .green : .secondary)
                    }
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)
            
            Text("セッションがありません")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Apple Watchでトレーニングを\n記録してください")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
    
    private var sessionsList: some View {
        List {
            ForEach(groupedSessions.keys.sorted(by: >), id: \.self) { date in
                Section {
                    ForEach(groupedSessions[date] ?? []) { session in
                        NavigationLink {
                            sessionDetailView(for: session)
                        } label: {
                            SessionRow(session: session)
                        }
                    }
                    .onDelete { indexSet in
                        let sessions = groupedSessions[date] ?? []
                        indexSet.forEach { i in
                            dataManager.deleteSession(sessions[i])
                        }
                    }
                } header: {
                    Text(formatSectionDate(date))
                }
            }
        }
        .refreshable {
            // Pull to Refreshでデータを再読み込み
            await refreshData()
        }
    }
    
    /// セッション詳細ビューを取得
    @ViewBuilder
    private func sessionDetailView(for session: TrainingSession) -> some View {
        if let gpsData = dataManager.getGPSData(for: session.id) {
            SessionDetailView(session: session, gpsData: gpsData)
        } else {
            VStack {
                Text("GPSデータが見つかりません")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // セッションを日付でグループ化
    private var groupedSessions: [Date: [TrainingSession]] {
        Dictionary(grouping: dataManager.sessions) { session in
            Calendar.current.startOfDay(for: session.date)
        }
    }
    
    private func formatSectionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ja_JP")
        
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今日"
        } else if calendar.isDateInYesterday(date) {
            return "昨日"
        } else {
            return formatter.string(from: date)
        }
    }
    
    /// Pull to Refreshでデータを再読み込み
    private func refreshData() async {
        print("🔄 データを再読み込み中...")
        dataManager.reloadSessions()
        print("✅ データ再読み込み完了: \(dataManager.sessions.count)件")
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: TrainingSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // セッション名と時間
            HStack {
                Text(session.name)
                    .font(.headline)
                
                Spacer()
                
                Text(formatTime(session.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // 統計サマリー
            HStack(spacing: 20) {
                StatBadge(
                    icon: "clock.fill",
                    value: formatDuration(session.duration),
                    color: .blue
                )
                
                StatBadge(
                    icon: "figure.walk",
                    value: formatDistance(session.totalDistance),
                    color: .green
                )
                
                StatBadge(
                    icon: "speedometer",
                    value: String(format: "%.1f m/s", session.maxSpeed),
                    color: .orange
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}

// MARK: - Stat Badge

struct StatBadge: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(color)
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    SessionsListView()
}
