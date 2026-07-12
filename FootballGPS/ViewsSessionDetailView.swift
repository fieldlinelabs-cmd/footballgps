//
//  SessionDetailView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import Combine
import Charts

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

    // スプリント区間（GPS速度から計算）
    @State private var sprintSegments: [SprintSegment] = []

    // 時間帯別運動量（5分単位）
    @State private var timeSeries: [TimeSeriesBucket] = []

    // 高強度分析（HR × スプリント）
    @State private var hrIntensity: (highIntensityRatio: Double, highIntensitySprintCount: Int)? = nil

    // プロスタイル診断
    @State private var syncResults: [StyleSyncResult] = []

    // フィールド変更シート
    @State private var showingFieldPicker = false

    // スプリント強調表示
    @State private var showSprints = true

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
        .sheet(isPresented: $showingFieldPicker) {
            fieldChangeSheet
        }
    }

    // MARK: - Field Change Sheet

    private var fieldChangeSheet: some View {
        NavigationStack {
            List(fieldManager.fields) { field in
                Button {
                    selectedFieldId = field.id
                    dataManager.updateFieldId(for: session.id, fieldId: field.id)
                    showingFieldPicker = false
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.name)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                            Text("\(Int(field.dimensions.length))m × \(Int(field.dimensions.width))m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if field.id == selectedFieldId {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
            .navigationTitle("フィールドを変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { showingFieldPicker = false }
                }
            }
        }
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
                currentPointIndex: currentPointIndex,
                sprintSegments: showSprints ? sprintSegments : []
            )
            .frame(height: 600)

            // スプリント表示切り替え
            Button {
                showSprints.toggle()
            } label: {
                Label(
                    showSprints ? "スプリント表示 ON" : "スプリント表示 OFF",
                    systemImage: showSprints ? "figure.run" : "figure.walk"
                )
                .font(.subheadline)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(showSprints ? Color.red.opacity(0.12) : Color(.systemGray6))
                .foregroundStyle(showSprints ? .red : .secondary)
                .clipShape(Capsule())
            }
            .padding(.horizontal)

            playbackControlsView

            fieldControlsRow
        }
        .onAppear {
            isPlaying = false
            currentTime = 0
            sprintSegments = SessionDataManager.computeSprintSegments(gpsData.points)
            timeSeries = SessionDataManager.computeTimeSeries(gpsPoints: gpsData.points)
            if let age = UserProfileManager.shared.age {
                hrIntensity = SessionDataManager.computeHeartRateIntensity(
                    gpsPoints: gpsData.points, age: age
                )
            }
            // 派生メトリクスが未保存なら算出して永続化（自己平均計算に使用）
            if session.staminaDrop == nil {
                let drop = SessionDataManager.computeStaminaDropRate(buckets: timeSeries)
                let hrRatio = hrIntensity?.highIntensityRatio
                dataManager.updateComputedMetrics(for: session.id, staminaDrop: drop, hrIntensityRatio: hrRatio)
            }
            if let field = currentField {
                let cnt = sprintSegments.isEmpty ? (session.sprintCount ?? 0) : sprintSegments.count
                syncResults = SessionDataManager.computeStyleSync(
                    gpsData: gpsData,
                    field: field,
                    isFlipped: isFlipped,
                    sprintCount: cnt,
                    agilityTurnCount: session.agilityTurnCount,
                    maxSpeed: session.maxSpeed
                )
            }
        }
        .onDisappear {
            isPlaying = false
        }
        .onChange(of: isFlipped) { _, flipped in
            if let field = currentField {
                let cnt = sprintSegments.isEmpty ? (session.sprintCount ?? 0) : sprintSegments.count
                syncResults = SessionDataManager.computeStyleSync(
                    gpsData: gpsData,
                    field: field,
                    isFlipped: flipped,
                    sprintCount: cnt,
                    agilityTurnCount: session.agilityTurnCount,
                    maxSpeed: session.maxSpeed
                )
            }
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
            
            fieldControlsRow
            
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

    // MARK: - Field Controls Row

    private var fieldControlsRow: some View {
        HStack(spacing: 12) {
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

            Button {
                showingFieldPicker = true
            } label: {
                Label("フィールドを変更", systemImage: "map")
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .foregroundStyle(.primary)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .padding(.horizontal)
    }
    
    // MARK: - Statistics View
    
    private func statisticsView(field: Field) -> some View {
        let thirdRatios = SessionDataManager.computeThirdRatios(
            gpsData: gpsData, field: field, isFlipped: isFlipped
        )
        let staminaDrop = SessionDataManager.computeStaminaDropRate(buckets: timeSeries)
        let sprintCnt = sprintSegments.isEmpty ? (session.sprintCount ?? 0) : sprintSegments.count
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: session.totalDistance,
            duration: session.duration,
            sprintCount: sprintCnt,
            agilityTurnCount: session.agilityTurnCount,
            staminaDrop: staminaDrop,
            hrIntensityRatio: hrIntensity?.highIntensityRatio,
            maxSpeed: session.maxSpeed
        )

        return VStack(alignment: .leading, spacing: 16) {
            Text("詳細統計")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 12) {
                StatisticRow(label: "総距離", value: formatDistance(session.totalDistance), icon: "figure.walk")
                StatisticRow(label: "時間", value: formatDuration(session.duration), icon: "clock.fill")
                StatisticRow(label: "平均速度", value: String(format: "%.2f m/s", session.avgSpeed), icon: "speedometer")
                StatisticRow(label: "最高速度", value: String(format: "%.2f m/s", session.maxSpeed), icon: "flame.fill")

                StatisticRow(
                    label: "スプリント回数",
                    value: sprintSegments.isEmpty && session.sprintCount == nil
                        ? "--"
                        : "\(sprintSegments.isEmpty ? (session.sprintCount ?? 0) : sprintSegments.count)回",
                    icon: "bolt.fill"
                )
                StatisticRow(
                    label: "アジリティ回数",
                    value: session.agilityTurnCount.map { "\($0)回" } ?? "--",
                    icon: "arrow.triangle.turn.up.right.diamond.fill"
                )

                if let bpm = session.heartRate, bpm > 0 {
                    StatisticRow(label: "心拍数", value: String(format: "%.0f bpm", bpm), icon: "heart.fill")
                }
                if let kcal = session.activeCalories, kcal > 0 {
                    StatisticRow(label: "消費カロリー", value: String(format: "%.0f kcal", kcal), icon: "flame.fill")
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)

            // プレイヤータイプ
            Text("プレイヤータイプ")
                .font(.headline)
                .padding(.horizontal)
            PlayerRadarSection(radar: radar, sessions: dataManager.sessions)

            // プロスタイル診断
            if !syncResults.isEmpty {
                Text("プロスタイル診断")
                    .font(.headline)
                    .padding(.horizontal)
                StyleSyncSection(results: Array(syncResults.prefix(3)))
            }

            // サード別滞在
            Text("サード別滞在")
                .font(.headline)
                .padding(.horizontal)

            ThirdRatioBarChart(
                defensive: thirdRatios.defensive,
                middle:    thirdRatios.middle,
                attacking: thirdRatios.attacking
            )

            // 時間帯別運動量
            if !timeSeries.isEmpty {
                Text("時間帯別運動量")
                    .font(.headline)
                    .padding(.horizontal)
                TimelineChartSection(
                    buckets: timeSeries,
                    staminaDrop: staminaDrop
                )
            }

            // 心拍数×強度分析
            if let intensity = hrIntensity {
                Text("心拍数強度分析")
                    .font(.headline)
                    .padding(.horizontal)
                IntensityAnalysisSection(intensity: intensity)
            }

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

// MARK: - Timeline Chart

struct TimelineChartSection: View {
    let buckets: [TimeSeriesBucket]
    let staminaDrop: Double?  // nil or ratio (secondHalf / firstHalf)

    private var mid: Int { buckets.count / 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 走行距離バーチャート
            Chart {
                ForEach(buckets) { bucket in
                    BarMark(
                        x: .value("時間", "\(bucket.startMinute)分"),
                        y: .value("距離", bucket.distance)
                    )
                    .foregroundStyle(bucket.id < mid ? Color.blue.opacity(0.7) : Color.orange.opacity(0.7))
                    .annotation(position: .top) {
                        if bucket.sprintCount > 0 {
                            Text("S\(bucket.sprintCount)")
                                .font(.system(size: 8))
                                .foregroundStyle(.red)
                        }
                    }
                }
                RuleMark(y: .value("ゼロ", 0))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.secondary)
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel()
                        .font(.system(size: 10))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))m")
                                .font(.system(size: 10))
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 160)

            // 凡例
            HStack(spacing: 16) {
                Label("前半", systemImage: "square.fill").foregroundStyle(.blue).font(.caption)
                Label("後半", systemImage: "square.fill").foregroundStyle(.orange).font(.caption)
                Spacer()
                Text("S=スプリント回数").font(.caption2).foregroundStyle(.secondary)
            }

            // スタミナフィードバック
            if let drop = staminaDrop {
                staminaFeedbackView(drop: drop)
            }

            // 5分サマリーカード
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(buckets) { bucket in
                        TimelineBucketCard(bucket: bucket)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private func staminaFeedbackView(drop: Double) -> some View {
        let pct = Int(drop * 100)
        HStack(spacing: 8) {
            Image(systemName: drop >= 0.85 ? "bolt.heart.fill" : "battery.25percent")
                .foregroundStyle(drop >= 0.85 ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(drop >= 0.85 ? "スタミナ維持: 後半も出力が安定しています" : "後半の運動量が前半比 \(pct)% に低下しています")
                    .font(.caption)
                    .fontWeight(.medium)
                Text(drop >= 0.85 ? "前後半の走行量がほぼ同じ「スタミナ型」です" : "スタミナ強化でさらに終盤も走れるようになります")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(drop >= 0.85 ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

private struct TimelineBucketCard: View {
    let bucket: TimeSeriesBucket

    var body: some View {
        VStack(spacing: 4) {
            Text("\(bucket.startMinute)-\(bucket.startMinute + 5)分")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.0fm", bucket.distance))
                .font(.subheadline)
                .fontWeight(.bold)
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(.red).font(.caption2)
                Text("\(bucket.sprintCount)").font(.caption2)
            }
            Text(String(format: "%.1fm/s", bucket.maxSpeed))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.06), radius: 2)
    }
}

// MARK: - Style Sync Section

struct StyleSyncSection: View {
    let results: [StyleSyncResult]

    var body: some View {
        VStack(spacing: 12) {
            if let top = results.first {
                // トップマッチ ヒーロー表示
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(top.style.category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(top.style.name)
                            .font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", top.syncRate))
                            .font(.title.bold())
                            .foregroundStyle(syncColor(rate: top.syncRate))
                        Text("シンクロ率")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // トップ3 ランキングバー
                ForEach(results) { result in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.style.name)
                                .font(.caption)
                            Text(result.style.category)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(.systemGray4))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(syncColor(rate: result.syncRate).opacity(0.75))
                                    .frame(width: geo.size.width * CGFloat(result.syncRate / 100))
                            }
                        }
                        .frame(height: 8)

                        Text(String(format: "%.0f%%", result.syncRate))
                            .font(.caption.monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func syncColor(rate: Double) -> Color {
        switch rate {
        case 70...: return .blue
        case 50..<70: return .green
        case 30..<50: return .orange
        default:      return .gray
        }
    }
}

// MARK: - Player Radar Section

struct PlayerRadarSection: View {
    let radar: PlayerRadarData
    let sessions: [TrainingSession]

    private let labels = ["走力", "スプリント", "アジリティ", "スタミナ", "高強度", "最高速度"]
    private var values: [Double] {
        [radar.distance, radar.sprint, radar.agility, radar.stamina, radar.intensity, radar.topSpeed]
    }

    // 案A: 研究ベースのアマチュア平均参照値（各軸の参照最大値に対する割合）
    // 走力100m/分・スプリント0.4/分・アジリティ3.0/分・スタミナ・HR高強度40%・最高速度8m/sを基準
    private let referenceA: [Double] = [0.80, 0.75, 0.67, 0.30, 0.75, 0.75]

    // 案C: 過去セッションの自己平均（GPS由来4軸はストレージから算出、HR依存軸は0）
    private var personalAvg: [Double]? {
        guard sessions.count >= 2 else { return nil }
        let radars = sessions.map { s in
            SessionDataManager.computePlayerRadar(
                totalDistance: s.totalDistance,
                duration: s.duration,
                sprintCount: s.sprintCount ?? 0,
                agilityTurnCount: s.agilityTurnCount,
                staminaDrop: s.staminaDrop,
                hrIntensityRatio: s.hrIntensityRatio,
                maxSpeed: s.maxSpeed
            )
        }
        let n = Double(radars.count)
        return [
            radars.map(\.distance).reduce(0, +) / n,
            radars.map(\.sprint).reduce(0, +) / n,
            radars.map(\.agility).reduce(0, +) / n,
            radars.map(\.stamina).reduce(0, +) / n,
            radars.map(\.intensity).reduce(0, +) / n,
            radars.map(\.topSpeed).reduce(0, +) / n
        ]
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: typeIcon)
                    .font(.title3)
                    .foregroundStyle(typeColor)
                Text(radar.playerType.rawValue)
                    .font(.title3.bold())
                    .foregroundStyle(typeColor)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("総合スコア")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f / 100", radar.overallScore))
                        .font(.callout.bold())
                }
            }

            RadarChartView(
                values: values,
                labels: labels,
                referenceA: referenceA,
                personalAvg: personalAvg
            )
            .frame(height: 220)

            // 凡例
            HStack(spacing: 16) {
                RadarLegendItem(color: .blue, dashed: false, label: "今回")
                if personalAvg != nil {
                    RadarLegendItem(color: .green, dashed: false, label: "自己平均")
                }
                RadarLegendItem(color: .gray, dashed: true, label: "アマ平均(参考)")
            }
            .font(.caption2)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private var typeIcon: String {
        switch radar.playerType {
        case .longRunner: return "figure.run"
        case .sprinter:   return "bolt.fill"
        case .agile:      return "arrow.triangle.turn.up.right.diamond.fill"
        case .stamina:    return "battery.100"
        case .hardWorker: return "flame.fill"
        case .speedster:  return "hare.fill"
        }
    }

    private var typeColor: Color {
        switch radar.playerType {
        case .longRunner: return .blue
        case .sprinter:   return .orange
        case .agile:      return .purple
        case .stamina:    return .green
        case .hardWorker: return .red
        case .speedster:  return .yellow
        }
    }
}

private struct RadarChartView: View {
    let values: [Double]          // 6要素、各 0…1（今回）
    let labels: [String]          // 6要素
    var referenceA: [Double]? = nil   // 案A: アマチュア平均
    var personalAvg: [Double]? = nil  // 案C: 自己過去平均

    private func hexagonPath(vals: [Double], cx: CGFloat, cy: CGFloat, r: CGFloat) -> Path {
        var path = Path()
        for i in 0..<6 {
            let angle = -Double.pi / 2 + Double(i) * Double.pi / 3
            let v = i < vals.count ? max(0, min(vals[i], 1.0)) : 0
            let pt = CGPoint(x: cx + CGFloat(cos(angle)) * r * CGFloat(v),
                             y: cy + CGFloat(sin(angle)) * r * CGFloat(v))
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }

    var body: some View {
        GeometryReader { geo in
            let cx     = geo.size.width  / 2
            let cy     = geo.size.height / 2
            let radius = min(geo.size.width, geo.size.height) / 2 - 34

            ZStack {
                Canvas { ctx, _ in
                    // グリッドリング（25/50/75/100%）
                    for level in stride(from: 0.25, through: 1.0, by: 0.25) {
                        let ring = hexagonPath(
                            vals: Array(repeating: Double(level), count: 6),
                            cx: cx, cy: cy, r: radius
                        )
                        ctx.stroke(ring, with: .color(.gray.opacity(0.25)), lineWidth: 1)
                    }
                    // 軸線
                    for i in 0..<6 {
                        let angle = -Double.pi / 2 + Double(i) * Double.pi / 3
                        var path = Path()
                        path.move(to: CGPoint(x: cx, y: cy))
                        path.addLine(to: CGPoint(
                            x: cx + CGFloat(cos(angle)) * radius,
                            y: cy + CGFloat(sin(angle)) * radius
                        ))
                        ctx.stroke(path, with: .color(.gray.opacity(0.25)), lineWidth: 1)
                    }

                    // 案A: アマチュア平均（グレー破線）
                    if let refA = referenceA {
                        let path = hexagonPath(vals: refA, cx: cx, cy: cy, r: radius)
                        ctx.stroke(path, with: .color(.gray.opacity(0.65)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }

                    // 案C: 自己過去平均（緑・半透明）
                    if let hist = personalAvg {
                        let path = hexagonPath(vals: hist, cx: cx, cy: cy, r: radius)
                        ctx.fill(path, with: .color(.green.opacity(0.12)))
                        ctx.stroke(path, with: .color(.green.opacity(0.65)), lineWidth: 1.5)
                    }

                    // 今回データポリゴン（青）
                    let dataPath = hexagonPath(vals: values, cx: cx, cy: cy, r: radius)
                    ctx.fill(dataPath, with: .color(.blue.opacity(0.25)))
                    ctx.stroke(dataPath, with: .color(.blue.opacity(0.75)), lineWidth: 2)
                }

                // ラベル
                ForEach(0..<min(6, labels.count), id: \.self) { i in
                    let angle = -Double.pi / 2 + Double(i) * Double.pi / 3
                    let lr    = radius + 22
                    Text(labels[i])
                        .font(.system(size: 10, weight: .medium))
                        .multilineTextAlignment(.center)
                        .position(
                            x: cx + CGFloat(cos(angle)) * lr,
                            y: cy + CGFloat(sin(angle)) * lr
                        )
                }
            }
        }
    }
}

private struct RadarLegendItem: View {
    let color: Color
    let dashed: Bool
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            if dashed {
                // 破線を模したアイコン
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in
                        Rectangle()
                            .fill(color.opacity(0.65))
                            .frame(width: 4, height: 1.5)
                    }
                }
                .frame(width: 14)
            } else {
                Circle()
                    .fill(color.opacity(0.5))
                    .frame(width: 8, height: 8)
            }
            Text(label)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Third Ratio Bar Chart

struct ThirdRatioBarChart: View {
    let defensive: Double
    let middle: Double
    let attacking: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ThirdBar(label: "守備", ratio: defensive, color: .blue)
            ThirdBar(label: "中盤", ratio: middle,    color: .green)
            ThirdBar(label: "攻撃", ratio: attacking, color: .orange)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}

private struct ThirdBar: View {
    let label: String
    let ratio: Double
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray4))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.8))
                        .frame(width: geo.size.width * CGFloat(ratio / 100))
                }
            }
            .frame(height: 16)
            Text(String(format: "%.0f%%", ratio))
                .font(.caption)
                .foregroundStyle(.primary)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Intensity Analysis Section

struct IntensityAnalysisSection: View {
    let intensity: (highIntensityRatio: Double, highIntensitySprintCount: Int)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("高強度割合")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f%%", intensity.highIntensityRatio))
                        .font(.title2.bold())
                        .foregroundStyle(intensityColor(ratio: intensity.highIntensityRatio))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("高強度スプリント")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(intensity.highIntensitySprintCount)回")
                        .font(.title2.bold())
                        .foregroundStyle(.orange)
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.systemGray4))
                        .frame(height: 12)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(intensityColor(ratio: intensity.highIntensityRatio).opacity(0.85))
                        .frame(width: geo.size.width * CGFloat(min(intensity.highIntensityRatio / 100, 1.0)), height: 12)
                }
            }
            .frame(height: 12)

            Text(intensityComment(ratio: intensity.highIntensityRatio))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func intensityColor(ratio: Double) -> Color {
        switch ratio {
        case ..<20: return .blue
        case ..<40: return .green
        case ..<60: return .yellow
        default:    return .red
        }
    }

    private func intensityComment(ratio: Double) -> String {
        switch ratio {
        case ..<20: return "低強度主体のセッション"
        case ..<40: return "適度な高強度運動ができています"
        case ..<60: return "高強度の割合が高いセッションです"
        default:    return "非常に高強度なセッションです"
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
