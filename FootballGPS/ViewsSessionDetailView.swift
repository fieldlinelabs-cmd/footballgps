//
//  SessionDetailView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import Combine

enum PlaybackSpeed: Double, CaseIterable {
    case x1  = 1.0
    case x2  = 2.0
    case x4  = 4.0
    case x8  = 8.0
    case x16 = 16.0

    var label: String {
        switch self {
        case .x1:  return "1x"
        case .x2:  return "2x"
        case .x4:  return "4x"
        case .x8:  return "8x"
        case .x16: return "16x"
        }
    }
}

struct SessionDetailView: View {
    let session: TrainingSession
    let gpsData: GPSData
    
    @State private var selectedTab = 0
    @State private var selectedFieldId: String?
    @State private var isFlipped: Bool
    @ObservedObject private var fieldManager = FieldManager.shared
    @ObservedObject private var dataManager = SessionDataManager.shared

    // 再生コントロール
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var playbackSpeed: PlaybackSpeed = .x8
    @State private var isDraggingSlider = false
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
    init(session: TrainingSession, gpsData: GPSData) {
        self.session = session
        self.gpsData = gpsData
        _selectedFieldId = State(initialValue: session.fieldId)
        _isFlipped = State(initialValue: session.isFlipped)
    }
    
    private var currentField: Field? {
        guard let id = selectedFieldId else { return nil }
        return fieldManager.getField(by: id)
    }

    private var totalDuration: TimeInterval {
        guard let first = gpsData.points.first,
              let last = gpsData.points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    private var currentPointIndex: Int {
        guard !gpsData.points.isEmpty,
              let firstTimestamp = gpsData.points.first?.timestamp else { return 0 }
        var lo = 0
        var hi = gpsData.points.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            let elapsed = gpsData.points[mid].timestamp.timeIntervalSince(firstTimestamp)
            if elapsed <= currentTime {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // セッション情報ヘッダー
                sessionHeader
                
                // フィールド未紐付けの場合はピッカーを表示
                if currentField == nil {
                    fieldPickerSection
                } else {
                    // タブ切り替え
                    Picker("表示", selection: $selectedTab) {
                        Text("ポジショニング").tag(0)
                        Text("ヒートマップ").tag(1)
                        Text("統計").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .font(.caption)
                    .padding(.horizontal)
                    
                    // コンテンツ
                    if let field = currentField {
                        Group {
                            switch selectedTab {
                            case 0:
                                positioningView(field: field)
                            case 1:
                                heatmapView(field: field)
                            case 2:
                                statisticsView(field: field)
                            default:
                                EmptyView()
                            }
                        }
                    }
                }
            }
            .padding(.bottom)
        }
        .navigationTitle(session.name)
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Field Picker
    
    private var fieldPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map.fill")
                    .foregroundStyle(.orange)
                Text("フィールドを選択してください")
                    .font(.headline)
            }
            .padding(.horizontal)
            
            if fieldManager.fields.isEmpty {
                VStack(spacing: 12) {
                    Text("フィールドが登録されていません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("「フィールド」タブからフィールドを登録してください")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    NavigationLink {
                        FieldsListView()
                    } label: {
                        Label("フィールドを登録", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
            } else {
                VStack(spacing: 8) {
                    ForEach(fieldManager.fields) { field in
                        Button {
                            selectedFieldId = field.id
                            dataManager.updateFieldId(for: session.id, fieldId: field.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(field.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("\(Int(field.dimensions.length))m × \(Int(field.dimensions.width))m")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
    
    // MARK: - Session Header
    
    private var sessionHeader: some View {
        VStack(spacing: 12) {
            Text(formatDate(session.date))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 30) {
                VStack {
                    Text(formatDuration(session.duration))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("時間")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text(formatDistance(session.totalDistance))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("距離")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                VStack {
                    Text(String(format: "%.1f", session.maxSpeed))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("最高速度 (m/s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Positioning View
    
    private func positioningView(field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldPositioningView(
                gpsData: gpsData,
                field: field,
                isFlipped: isFlipped,
                currentPointIndex: currentPointIndex
            )
            .frame(height: 600)

            playbackControlsView

            flipButton
        }
        .onAppear {
            isPlaying = false
            currentTime = 0
        }
        .onDisappear {
            isPlaying = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { isPlaying = false }
        }
        .onReceive(timer) { _ in
            guard isPlaying && !isDraggingSlider && totalDuration > 0 else { return }
            currentTime += 0.05 * playbackSpeed.rawValue
            if currentTime >= totalDuration {
                currentTime = 0
                isPlaying = false
            }
        }
    }
    
    // MARK: - Heatmap View
    
    private func heatmapView(field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            FieldHeatmapView(gpsData: gpsData, field: field, isFlipped: isFlipped)
                .frame(height: 600)
            
            flipButton
            
            Text("赤い部分ほど長時間滞在したエリアです")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
    }
    
    // MARK: - Playback Controls

    private var playbackControlsView: some View {
        VStack(spacing: 8) {
            // 行A: 時刻表示 + 速度メニュー
            HStack {
                Text("\(formatPlaybackTime(currentTime)) / \(formatPlaybackTime(totalDuration))")
                    .font(.caption)
                    .monospacedDigit()

                Spacer()

                Menu {
                    ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                        Button {
                            playbackSpeed = speed
                        } label: {
                            if speed == playbackSpeed {
                                Label(speed.label, systemImage: "checkmark")
                            } else {
                                Text(speed.label)
                            }
                        }
                    }
                } label: {
                    Text(playbackSpeed.label)
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .clipShape(Capsule())
                }
            }

            // 行B: スライダー
            Slider(
                value: Binding(
                    get: { totalDuration > 0 ? currentTime / totalDuration : 0 },
                    set: { currentTime = $0 * totalDuration }
                ),
                in: 0...1
            ) { editing in
                isDraggingSlider = editing
            }
            .tint(.blue)
            .disabled(totalDuration == 0)

            // 行C: 再生ボタン群
            HStack(spacing: 0) {
                Button {
                    currentTime = 0
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    currentTime = max(0, currentTime - 10)
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                }

                Spacer()

                Button {
                    currentTime = min(totalDuration, currentTime + 10)
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title2)
                        .foregroundStyle(.primary)
                }

                Spacer()

                Button {
                    currentTime = totalDuration
                    isPlaying = false
                } label: {
                    Image(systemName: "forward.end.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func formatPlaybackTime(_ time: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }

    // MARK: - Flip Button

    private var flipButton: some View {
        Button {
            isFlipped.toggle()
            dataManager.updateIsFlipped(for: session.id, isFlipped: isFlipped)
        } label: {
            Label(
                isFlipped ? "コート入れ替え ✓" : "コート入れ替え",
                systemImage: "arrow.left.arrow.right"
            )
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(isFlipped ? Color.blue.opacity(0.15) : Color(.systemGray6))
            .foregroundStyle(isFlipped ? .blue : .primary)
            .clipShape(Capsule())
        }
        .padding(.horizontal)
    }
    
    // MARK: - Statistics View
    
    private func statisticsView(field: Field) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("詳細統計")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                StatisticRow(label: "総距離", value: formatDistance(session.totalDistance), icon: "figure.walk")
                StatisticRow(label: "時間", value: formatDuration(session.duration), icon: "clock.fill")
                StatisticRow(label: "平均速度", value: String(format: "%.2f m/s", session.avgSpeed), icon: "speedometer")
                StatisticRow(label: "最高速度", value: String(format: "%.2f m/s", session.maxSpeed), icon: "flame.fill")
                
                if let sprintCount = session.sprintCount {
                    StatisticRow(label: "スプリント回数", value: "\(sprintCount)回", icon: "bolt.fill")
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // デバッグ情報
            Text("デバッグ情報")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                StatisticRow(label: "GPSポイント数", value: "\(gpsData.points.count)点", icon: "location.fill")
                StatisticRow(label: "フィールド", value: field.name, icon: "map")
                StatisticRow(label: "フィールドサイズ", value: "\(Int(field.dimensions.length))m × \(Int(field.dimensions.width))m", icon: "ruler")
                
                // 座標範囲
                if let first = gpsData.points.first, let last = gpsData.points.last {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GPS範囲:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  開始: \(String(format: "%.6f", first.latitude)), \(String(format: "%.6f", first.longitude))")
                            .font(.caption2)
                        Text("  終了: \(String(format: "%.6f", last.latitude)), \(String(format: "%.6f", last.longitude))")
                            .font(.caption2)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("フィールド範囲:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("  左上: \(String(format: "%.6f", field.corners.topLeft.latitude)), \(String(format: "%.6f", field.corners.topLeft.longitude))")
                            .font(.caption2)
                        Text("  右下: \(String(format: "%.6f", field.corners.bottomRight.latitude)), \(String(format: "%.6f", field.corners.bottomRight.longitude))")
                            .font(.caption2)
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return "\(hours)時間\(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }
    
    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}

// MARK: - Statistic Row

struct StatisticRow: View {
    let label: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 30)
                .foregroundStyle(.blue)
            
            Text(label)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    NavigationStack {
        SessionDetailView(
            session: MockData.mockSessions[0],
            gpsData: MockData.generateMockGPSData(sessionId: MockData.mockSessions[0].id)
        )
    }
}
