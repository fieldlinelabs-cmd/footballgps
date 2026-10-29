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
    @State private var heartRateSeries: [HeartRateSample] = []
    @State private var heartRateSummary: HeartRateSummary? = nil
    @State private var showingShareCard = false

    // プロスタイル診断
    @State private var syncDiagnosis: StyleSyncDiagnosis?

    // フィールド変更シート
    @State private var showingFieldPicker = false

    // ポジション選択シート
    @State private var showingPositionPicker = false

    // スプリント強調表示
    @State private var showSprints = true

    // 再生コントロール
    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var playbackSpeed: PlaybackSpeed = .x8
    @State private var isDraggingSlider = false
    @Environment(\.scenePhase) private var scenePhase
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    // ドリルの手動切り出し
    @State private var showManualSplit = false

    // ドリル分割の復元
    @State private var showRestoreSplitConfirm = false
    @Environment(\.dismiss) private var dismiss

    // ドリル分割の再検出
    @State private var showSplitDetectionResult = false
    @State private var splitDetectionFoundCount: Int? = nil
    
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

    /// dataManager.sessions 内の最新値（派生メトリクスの再計算値等）を反映するセッション参照。
    /// session（let）は識別子など変化しないフィールド用に残す。
    private var displaySession: TrainingSession {
        dataManager.sessions.first(where: { $0.id == session.id }) ?? session
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // セッション情報ヘッダー
                sessionHeader
                
                // フィールド未紐付けの場合はピッカーを表示
                if currentField == nil {
                    fieldPickerSection
                    TodayPerformanceCard(session: displaySession, sessions: dataManager.sessions)
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
        .toolbar {
            // 結果カードの共有（技術実装仕様書 §26）。ヒートマップを載せるため、フィールドが決まっているときだけ
            if currentField != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingShareCard = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("結果を共有")
                }
            }
        }
        .sheet(isPresented: $showingShareCard) {
            if let field = currentField {
                ShareCardSheet(data: shareCardData(), gpsData: gpsData, field: field, isFlipped: isFlipped)
            }
        }
        .sheet(isPresented: $showingFieldPicker) {
            fieldChangeSheet
        }
        .sheet(isPresented: $showingPositionPicker) {
            PositionPickerSheet(session: displaySession)
        }
        // 見終わった後のインタースティシャル広告（広告仕様書§4.2.1）。一覧へ戻る・別タブへ切り替えで離れたときに判定する
        .onAppear { InterstitialAdManager.shared.detailDidAppear(sessionId: session.id) }
        .onDisappear { InterstitialAdManager.shared.detailDidDisappear(sessionId: session.id) }
    }

    // MARK: - Share Card

    /// 結果カードに載せる値。統計タブと同じ計算で求める
    private func shareCardData() -> ShareCardData {
        let sprintCnt = sprintSegments.isEmpty ? (displaySession.sprintCount ?? 0) : sprintSegments.count
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: displaySession.totalDistance,
            duration: displaySession.duration,
            sprintCount: sprintCnt,
            agilityTurnCount: displaySession.agilityTurnCount,
            staminaDrop: SessionDataManager.computeStaminaDropRate(buckets: timeSeries),
            hrIntensityRatio: hrIntensity?.highIntensityRatio,
            maxSpeed: displaySession.maxSpeed
        )
        return ShareCardData(
            date: displaySession.date,
            position: displaySession.position,
            playerType: radar.playerType,
            proStyle: syncDiagnosis?.typeResults.first.map { ($0.style.name, $0.syncRate) },
            totalDistance: displaySession.totalDistance,
            maxSpeed: displaySession.maxSpeed,
            sprintCount: sprintCnt,
            duration: displaySession.duration,
            averageHeartRate: heartRateSummary?.averageBPM
        )
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

            PositionChip(session: displaySession) {
                showingPositionPicker = true
            }

            HStack(spacing: 30) {
                VStack {
                    Text(formatDuration(displaySession.duration))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("時間")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text(formatDistance(displaySession.totalDistance))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("距離")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack {
                    Text(String(format: "%.1f", displaySession.maxSpeed * 3.6))
                        .font(.title)
                        .fontWeight(.bold)
                    Text("最高速度 (km/h)")
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

            HStack(spacing: 8) {
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

                // ドリルを切り出す（分割で作られたセッション・分割済みの元記録は対象外）
                if displaySession.splitFromSessionId == nil && !displaySession.isSupersededBySplit {
                    Button {
                        isPlaying = false
                        showManualSplit = true
                    } label: {
                        Label("ドリルを切り出す", systemImage: "scissors")
                            .font(.subheadline)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.orange.opacity(0.12))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)

            playbackControlsView

            if displaySession.splitFromSessionId != nil {
                HStack {
                    Text("🔀 ドリル分割で作成されたセッションです")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                    Spacer()
                    Button("分割前の記録に戻す") {
                        showRestoreSplitConfirm = true
                    }
                    .font(.caption2)
                }
                .padding(.horizontal)
            } else if displaySession.pendingSplitBreaks == nil && !displaySession.isSupersededBySplit {
                // 分割で作られたセッションでもなく、分割候補が未検出（=元に戻した直後や、
                // 過去に検出できなかった記録）の場合、手動で再検出できるようにする
                HStack {
                    Text("休憩を自動検知してドリルに分割できます")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("ドリル分割を検出する") {
                        dataManager.analyzeForDrillSplits(sessionId: displaySession.id)
                        let updated = dataManager.sessions.first(where: { $0.id == displaySession.id })
                        if let breaks = updated?.pendingSplitBreaks, !breaks.isEmpty {
                            let ranges = DrillSplitDetector.segmentRanges(totalDuration: displaySession.duration, breaks: breaks)
                            splitDetectionFoundCount = ranges.count
                        } else {
                            splitDetectionFoundCount = nil
                        }
                        showSplitDetectionResult = true
                    }
                    .font(.caption2)
                }
                .padding(.horizontal)
            }

            fieldControlsRow
        }
        .sheet(isPresented: $showManualSplit) {
            NavigationStack {
                DrillSplitManualEditView(
                    session: displaySession,
                    gpsData: gpsData,
                    field: field,
                    isFlipped: isFlipped,
                    initialRanges: pendingDrillRanges,
                    onConfirmed: {
                        showManualSplit = false
                        // 元のセッションは分割済みとして一覧から消えるため、詳細画面も閉じる
                        dismiss()
                    }
                )
            }
        }
        .confirmationDialog(
            "分割前の1本の記録に戻しますか？",
            isPresented: $showRestoreSplitConfirm,
            titleVisibility: .visible
        ) {
            Button("元に戻す", role: .destructive) {
                if let originalId = displaySession.splitFromSessionId {
                    dataManager.restoreSplit(originalSessionId: originalId)
                }
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("このドリルを含む、分割後のセッションはすべて削除されます。")
        }
        .alert(
            splitDetectionFoundCount != nil ? "ドリル分割の候補を検出しました" : "分割候補は見つかりませんでした",
            isPresented: $showSplitDetectionResult
        ) {
            Button("OK") {}
        } message: {
            if let count = splitDetectionFoundCount {
                Text("\(count)本のドリルを検出しました。セッション一覧のバッジから確認してください。")
            } else {
                Text("フィールド外での休憩が検出できなかったか、各ドリルが短すぎた可能性があります。")
            }
        }
        .onAppear {
            isPlaying = false
            currentTime = 0
            sprintSegments = SessionDataManager.computeSprintSegments(gpsData.points)
            timeSeries = SessionDataManager.computeTimeSeries(gpsPoints: gpsData.points)
            heartRateSeries = HeartRateAnalysis.series(for: gpsData)
            heartRateSummary = HeartRateAnalysis.summarize(heartRateSeries, age: UserProfileManager.shared.age)
            if let age = UserProfileManager.shared.age {
                hrIntensity = SessionDataManager.computeHeartRateIntensity(
                    gpsPoints: gpsData.points, heartRateSamples: gpsData.heartRateSamples, age: age
                )
            }
            // sprintCount は記録時点の古い閾値で保存されている場合があるため、
            // staminaDrop計算済みかどうかに関わらず、現在の閾値で再計算した値とズレていれば同期する
            let sprintCnt = sprintSegments.isEmpty ? (displaySession.sprintCount ?? 0) : sprintSegments.count
            // 派生メトリクスが未保存なら算出して永続化し、Supabaseにアップロード（初回閲覧時）
            if displaySession.staminaDrop == nil {
                let drop = SessionDataManager.computeStaminaDropRate(buckets: timeSeries)
                let hrRatio = hrIntensity?.highIntensityRatio
                dataManager.updateComputedMetrics(for: session.id, staminaDrop: drop, hrIntensityRatio: hrRatio, sprintCount: sprintCnt)
                let radar = SessionDataManager.computePlayerRadar(
                    totalDistance: displaySession.totalDistance,
                    duration: displaySession.duration,
                    sprintCount: sprintCnt,
                    agilityTurnCount: displaySession.agilityTurnCount,
                    staminaDrop: drop,
                    hrIntensityRatio: hrRatio,
                    maxSpeed: displaySession.maxSpeed
                )
                // session は値型のため updateComputedMetrics の変更を反映していない。
                // staminaDrop/hrIntensityRatio/sprintCount は今計算した値を明示的に上書きしてからアップロードする。
                // sprintCount は session.sprintCount（記録時点の古い閾値での値）ではなく、
                // 現在のプロフィール（年齢・性別）の閾値で再計算した sprintCnt を使う（radar計算と同じ値に揃える）
                var updatedSession = displaySession
                updatedSession.staminaDrop = drop
                updatedSession.hrIntensityRatio = hrRatio
                updatedSession.sprintCount = sprintCnt
                Task {
                    do {
                        try await SupabaseManager.shared.uploadSessionSummary(updatedSession, radar: radar)
                        print("✅ Supabaseへの派生メトリクス再同期完了: id=\(updatedSession.id) duration=\(updatedSession.duration)")
                    } catch {
                        print("❌ Supabaseへの派生メトリクス再同期に失敗: id=\(updatedSession.id) error=\(error)")
                    }
                }
            } else if displaySession.sprintCount != sprintCnt {
                // staminaDropは計算済みだが、sprintCountだけ古い閾値の値のまま残っているセッションを同期
                dataManager.updateComputedMetrics(
                    for: session.id,
                    staminaDrop: displaySession.staminaDrop,
                    hrIntensityRatio: displaySession.hrIntensityRatio,
                    sprintCount: sprintCnt
                )
                let radar = SessionDataManager.computePlayerRadar(
                    totalDistance: displaySession.totalDistance,
                    duration: displaySession.duration,
                    sprintCount: sprintCnt,
                    agilityTurnCount: displaySession.agilityTurnCount,
                    staminaDrop: displaySession.staminaDrop,
                    hrIntensityRatio: displaySession.hrIntensityRatio,
                    maxSpeed: displaySession.maxSpeed
                )
                var updatedSession = displaySession
                updatedSession.sprintCount = sprintCnt
                Task {
                    do {
                        try await SupabaseManager.shared.uploadSessionSummary(updatedSession, radar: radar)
                        print("✅ Supabaseへの派生メトリクス再同期完了: id=\(updatedSession.id) duration=\(updatedSession.duration)")
                    } catch {
                        print("❌ Supabaseへの派生メトリクス再同期に失敗: id=\(updatedSession.id) error=\(error)")
                    }
                }
            }
            if let field = currentField {
                syncDiagnosis = SessionDataManager.computeStyleSync(
                    gpsData: gpsData,
                    field: field,
                    isFlipped: isFlipped,
                    sprintCount: sprintCnt,
                    agilityTurnCount: displaySession.agilityTurnCount,
                    maxSpeed: displaySession.maxSpeed
                )
            }
        }
        .onDisappear {
            isPlaying = false
        }
        .onChange(of: isFlipped) { _, flipped in
            if let field = currentField {
                let cnt = sprintSegments.isEmpty ? (displaySession.sprintCount ?? 0) : sprintSegments.count
                syncDiagnosis = SessionDataManager.computeStyleSync(
                    gpsData: gpsData,
                    field: field,
                    isFlipped: flipped,
                    sprintCount: cnt,
                    agilityTurnCount: displaySession.agilityTurnCount,
                    maxSpeed: displaySession.maxSpeed
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

    // MARK: - Manual Drill Split

    /// 自動検出の分割候補があれば、そのドリル区間（手動切り出し画面の初期状態に使う）
    private var pendingDrillRanges: [(start: TimeInterval, end: TimeInterval)] {
        guard let breaks = displaySession.pendingSplitBreaks, !breaks.isEmpty else { return [] }
        return DrillSplitDetector.segmentRanges(totalDuration: displaySession.duration, breaks: breaks)
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
        let sprintCnt = sprintSegments.isEmpty ? (displaySession.sprintCount ?? 0) : sprintSegments.count
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: displaySession.totalDistance,
            duration: displaySession.duration,
            sprintCount: sprintCnt,
            agilityTurnCount: displaySession.agilityTurnCount,
            staminaDrop: staminaDrop,
            hrIntensityRatio: hrIntensity?.highIntensityRatio,
            maxSpeed: displaySession.maxSpeed
        )

        return VStack(alignment: .leading, spacing: 16) {
            TodayPerformanceCard(session: displaySession, sessions: dataManager.sessions)

            Text("詳細統計")
                .font(.headline)
                .padding(.horizontal)

            VStack(spacing: 12) {
                StatisticRow(label: "総距離", value: formatDistance(displaySession.totalDistance), icon: "figure.walk")
                StatisticRow(label: "時間", value: formatDuration(displaySession.duration), icon: "clock.fill")
                StatisticRow(label: "平均速度", value: String(format: "%.1f km/h", displaySession.avgSpeed * 3.6), icon: "speedometer")
                StatisticRow(label: "最高速度", value: String(format: "%.1f km/h", displaySession.maxSpeed * 3.6), icon: "flame.fill")

                StatisticRow(
                    label: "スプリント回数",
                    value: sprintSegments.isEmpty && displaySession.sprintCount == nil
                        ? "--"
                        : "\(sprintSegments.isEmpty ? (displaySession.sprintCount ?? 0) : sprintSegments.count)回",
                    icon: "bolt.fill"
                )
                StatisticRow(
                    label: "アジリティ回数",
                    value: displaySession.agilityTurnCount.map { "\($0)回" } ?? "--",
                    icon: "arrow.triangle.turn.up.right.diamond.fill"
                )

                if let summary = heartRateSummary {
                    StatisticRow(label: "平均心拍", value: String(format: "%.0f bpm", summary.averageBPM), icon: "heart.fill")
                    StatisticRow(label: "最大心拍", value: String(format: "%.0f bpm", summary.maxBPM), icon: "heart.circle.fill")
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

            // AI監督フィードバック（§20.7: プレイヤータイプ直後・プロスタイル診断の前に配置）
            AICoachFeedbackSection(
                session: session,
                defaultPosition: displaySession.position?.displayName,
                sessionSummary: SessionDataManager.buildFeedbackSummaryText(
                    session: displaySession,
                    thirdRatios: thirdRatios,
                    staminaDropRate: staminaDrop,
                    radar: radar,
                    sprintCount: sprintCnt,
                    heartRate: heartRateSummary,
                    heartRateHalves: HeartRateAnalysis.halfAverages(
                        heartRateSeries, start: gpsData.points.first?.timestamp ?? displaySession.date, buckets: timeSeries
                    )
                )
            )

            // プロスタイル診断
            if let diagnosis = syncDiagnosis {
                Text("プロスタイル診断")
                    .font(.headline)
                    .padding(.horizontal)
                StyleSyncSection(diagnosis: diagnosis)
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
                    staminaDrop: staminaDrop,
                    heartRateByBucket: HeartRateAnalysis.bucketAverages(
                        heartRateSeries, start: gpsData.points.first?.timestamp ?? displaySession.date, buckets: timeSeries
                    ),
                    heartRateHalves: HeartRateAnalysis.halfAverages(
                        heartRateSeries, start: gpsData.points.first?.timestamp ?? displaySession.date, buckets: timeSeries
                    )
                )
            }

            // 心拍の推移とゾーン（技術実装仕様書 §25.5）
            if let summary = heartRateSummary {
                Text("心拍")
                    .font(.headline)
                    .padding(.horizontal)
                HeartRateSection(
                    series: heartRateSeries,
                    summary: summary,
                    startDate: gpsData.points.first?.timestamp ?? heartRateSeries.first?.timestamp ?? displaySession.date
                )
                if let intensity = hrIntensity {
                    IntensityAnalysisSection(intensity: intensity)
                }
            }

            // デバッグ情報
            Text("デバッグ情報")
                .font(.headline)
                .padding(.horizontal)
            
            VStack(spacing: 12) {
                StatisticRow(label: "GPSポイント数（生データ）", value: "\(gpsData.points.count)点", icon: "location.fill")
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
    /// 各区間の平均心拍（技術実装仕様書 §25.8）。心拍の記録がなければ空
    var heartRateByBucket: [Double?] = []
    /// 前半・後半の平均心拍。心拍の記録がなければ nil
    var heartRateHalves: (first: Double, second: Double)? = nil

    private var mid: Int { buckets.count / 2 }

    /// 走行距離と心拍の2つのグラフで横軸の位置をそろえるため、縦軸の目盛りの幅を固定する
    private let yAxisLabelWidth: CGFloat = 40

    private var hasHeartRate: Bool { heartRateByBucket.contains { $0 != nil } }

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
                                .frame(width: yAxisLabelWidth, alignment: .trailing)
                        }
                    }
                    AxisGridLine()
                }
            }
            .frame(height: 160)

            if hasHeartRate {
                heartRateChart
            }

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
                if let halves = heartRateHalves {
                    heartRateHalvesView(drop: drop, halves: halves)
                }
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

    /// 5分ごとの平均心拍（走行距離の棒グラフと横軸をそろえる）
    private var heartRateChart: some View {
        let values = heartRateByBucket.compactMap { $0 }
        let lower = max(0, (values.min() ?? 60) - 10)
        let upper = (values.max() ?? 180) + 10
        return Chart {
            ForEach(Array(zip(buckets, heartRateByBucket)), id: \.0.id) { bucket, bpm in
                if let bpm {
                    LineMark(
                        x: .value("時間", "\(bucket.startMinute)分"),
                        y: .value("心拍", bpm)
                    )
                    .foregroundStyle(.red)
                    PointMark(
                        x: .value("時間", "\(bucket.startMinute)分"),
                        y: .value("心拍", bpm)
                    )
                    .foregroundStyle(.red)
                    .symbolSize(20)
                }
            }
        }
        .chartXScale(domain: buckets.map { "\($0.startMinute)分" })
        .chartYScale(domain: lower...upper)
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
                        Text("\(Int(v))")
                            .font(.system(size: 10))
                            .frame(width: yAxisLabelWidth, alignment: .trailing)
                    }
                }
                AxisGridLine()
            }
        }
        .chartYAxisLabel("平均心拍 (bpm)", position: .top, alignment: .leading)
        .frame(height: 110)
    }

    /// 走行量の変化と心拍の変化を組み合わせた一言（§25.8）
    private func heartRateHalvesView(drop: Double, halves: (first: Double, second: Double)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "heart.text.square.fill")
                .foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(HeartRateAnalysis.halfComment(staminaDrop: drop, firstBPM: halves.first, secondBPM: halves.second))
                    .font(.caption)
                    .fontWeight(.medium)
                Text(String(format: "平均心拍 前半 %.0f bpm → 後半 %.0f bpm", halves.first, halves.second))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.08))
        .cornerRadius(8)
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
            Text("\(bucket.startMinute)-\(bucket.startMinute + Int(bucket.durationSeconds / 60.0))分")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(String(format: "%.0fm", bucket.distance))
                .font(.subheadline)
                .fontWeight(.bold)
            HStack(spacing: 4) {
                Image(systemName: "bolt.fill").foregroundStyle(.red).font(.caption2)
                Text("\(bucket.sprintCount)").font(.caption2)
            }
            Text(String(format: "%.1fkm/h", bucket.maxSpeed * 3.6))
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

// MARK: - AI監督フィードバック（§20）

struct AICoachFeedbackSection: View {
    let session: TrainingSession
    /// ポジション入力欄が空のときの初期値（セッションに設定したポジション、統計推移仕様書 §4.3）
    let defaultPosition: String?
    let sessionSummary: String

    @ObservedObject private var adManager = RewardedAdManager.shared
    @State private var personaInput: String = ""
    @State private var positionInput: String = ""
    @State private var isGenerating = false
    @State private var currentResult: AICoachFeedbackResult?
    @State private var currentPersona: String = ""
    @State private var currentPosition: String?
    @State private var history: [AICoachFeedbackRow] = []
    @State private var errorMessage: String?
    @State private var showNoAdNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI監督フィードバック")
                .font(.headline)

            Text("監督名やチーム名を入力すると、その指導スタイルになりきったAIが今回のプレーを分析します。ポジションも入力すると、より的確な指摘になります。")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("例: ペップ・グアルディオラ", text: $personaInput)
                .textFieldStyle(.roundedBorder)
                .disabled(isGenerating)

            TextField("あなたのポジション（任意・例: ボランチ）", text: $positionInput)
                .textFieldStyle(.roundedBorder)
                .disabled(isGenerating)

            Button {
                Task { await generate(persona: personaInput, position: positionInput) }
            } label: {
                Group {
                    if isGenerating {
                        ProgressView()
                    } else {
                        Text("広告を見て分析結果を見る")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(personaInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)

            if showNoAdNotice {
                Text("広告が表示できなかったため、そのまま分析します")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let result = currentResult {
                resultCards(result: result, persona: currentPersona, position: currentPosition)
            }

            if !history.isEmpty {
                historyChips
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .onAppear {
            adManager.preload()
            if positionInput.isEmpty, let defaultPosition {
                positionInput = defaultPosition
            }
            Task { await loadHistory() }
        }
    }

    @ViewBuilder
    private func resultCards(result: AICoachFeedbackResult, persona: String, position: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !result.personaRecognized {
                Text("『\(persona)』に関する十分な情報がないため、一般的な指導者の視点からの分析です")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.thumbsup.fill")
                    .foregroundStyle(.green)
                Text(result.positive)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.green.opacity(0.12))
            .cornerRadius(10)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "arrow.up.forward.circle.fill")
                    .foregroundStyle(.orange)
                Text(result.improvement)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.orange.opacity(0.12))
            .cornerRadius(10)

            // 同じ呼び出しで生成された二つ名（§24）。Player Dataの称号にも反映される
            if let nickname = result.nickname {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("二つ名「\(nickname)」")
                            .font(.subheadline.bold())
                        if let reason = result.nicknameReason {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(10)
            }

            Button("もう一度やり直す") {
                Task { await generate(persona: persona, position: position ?? "") }
            }
            .font(.caption)
            .disabled(isGenerating)

            Text("AIによる創作コメントであり、実在の人物・チームの実際の見解ではありません")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var historyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(history) { row in
                    Button {
                        currentResult = AICoachFeedbackResult(row: row)
                        currentPersona = row.persona
                        currentPosition = row.position
                        personaInput = row.persona
                        positionInput = row.position ?? ""
                    } label: {
                        VStack(spacing: 2) {
                            Text(row.persona)
                                .font(.caption2)
                            Text(row.createdAt, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Actions

    private func generate(persona: String, position: String) async {
        let trimmed = persona.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let trimmedPosition = position.trimmingCharacters(in: .whitespacesAndNewlines)
        let position: String? = trimmedPosition.isEmpty ? nil : trimmedPosition

        isGenerating = true
        errorMessage = nil
        showNoAdNotice = false
        defer { isGenerating = false }

        guard let viewController = UIViewController.currentForPresentation else {
            errorMessage = "画面の準備ができていません。もう一度お試しください。"
            return
        }

        do {
            let ticketId = try await SupabaseManager.shared.createAdTicket(
                localSessionId: session.id,
                persona: trimmed
            )

            let presentResult = await adManager.presentAndWaitForReward(
                ticketId: ticketId,
                from: viewController
            )

            // リワード広告を見た閲覧では、戻るときのインタースティシャルを出さない（広告仕様書§4.2.1）
            if presentResult != .noFill {
                InterstitialAdManager.shared.markRewardedAdWatched(sessionId: session.id)
            }

            switch presentResult {
            case .rewarded:
                try await fetchWithFreeRetry(ticketId: ticketId, persona: trimmed, position: position)
            case .notRewarded:
                break // 広告を最後まで見なかったので何もしない
            case .noFill:
                showNoAdNotice = true
                try await fetchWithFreeRetry(ticketId: nil, persona: trimmed, position: position)
            }
        } catch let error as AICoachFeedbackError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "分析中にエラーが発生しました。もう一度お試しください。"
        }
    }

    /// 広告視聴後にAPI呼び出しが失敗した場合、同じticketで無料の1回だけ即時リトライする（§20.6）。
    /// Edge Function側は成功時のみticketを消費するため、失敗時の再送は追加の広告視聴を必要としない。
    private func fetchWithFreeRetry(ticketId: String?, persona: String, position: String?) async throws {
        do {
            try await fetchAndApply(ticketId: ticketId, persona: persona, position: position)
        } catch {
            try await fetchAndApply(ticketId: ticketId, persona: persona, position: position)
        }
    }

    private func fetchAndApply(ticketId: String?, persona: String, position: String?) async throws {
        let result = try await SupabaseManager.shared.fetchAICoachFeedback(
            ticketId: ticketId,
            localSessionId: session.id,
            persona: persona,
            position: position,
            sessionSummary: sessionSummary
        )
        currentResult = result
        currentPersona = persona
        currentPosition = position
        await loadHistory()
    }

    private func loadHistory() async {
        history = (try? await SupabaseManager.shared.fetchCachedFeedbacks(localSessionId: session.id)) ?? []

        // 画面再表示時（他セッションを開いて戻ってきた場合等）に、直近の生成結果を
        // 自動的にメイン表示へ復元する。広告・API呼び出しは発生しない（キャッシュのみ）。
        if currentResult == nil, let latest = history.first {
            currentResult = AICoachFeedbackResult(row: latest)
            currentPersona = latest.persona
            currentPosition = latest.position
            personaInput = latest.persona
            positionInput = latest.position ?? positionInput
        }
    }
}

// MARK: - Style Sync Section

struct StyleSyncSection: View {
    let diagnosis: StyleSyncDiagnosis

    var body: some View {
        VStack(spacing: 12) {
            // ステップ1: ポジション判定（ヒートマップ空間類似度のみ）
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ポジション")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(diagnosis.position.category.diagnosisLabel)
                        .font(.title3.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "%.0f%%", diagnosis.position.positionScore))
                        .font(.title2.bold())
                        .foregroundStyle(syncColor(rate: diagnosis.position.positionScore))
                    Text("ヒートマップ一致度")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if let top = diagnosis.typeResults.first {
                // ステップ2: タイプ判定（スタッツ類似度50% + サード滞在比率50%）
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("タイプ")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(top.style.name)
                            .font(.title3.bold())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "%.0f%%", top.syncRate))
                            .font(.title2.bold())
                            .foregroundStyle(syncColor(rate: top.syncRate))
                        Text("スタッツ・サード一致度")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // タイプ候補ランキングバー
                ForEach(diagnosis.typeResults) { result in
                    HStack(spacing: 8) {
                        Text(result.style.name)
                            .font(.caption)
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

    // 案A: 研究ベースのアマチュア平均参照値（各軸のMax定数に対する割合、2026-07-20見直し）
    // 走力130m/分・スプリント1.0/分・アジリティ4.5/分・スタミナ・HR高強度100%（自己指標）・最高速度8m/sを基準
    // アマ平均の絶対値（走力80m/分・スプリント0.3回/分・アジリティ2.0回/分・高強度30%・最高速度21.6km/h）自体は
    // 研究値のまま変更していない。Max定数の変更に合わせて比率のみ再計算した
    private let referenceA: [Double] = [80.0 / 130.0, 0.3 / 1.0, 2.0 / 4.5, 0.30, 30.0 / 100.0, 0.75]

    // 案C: 直近5回の自己平均（5分未満・手動除外は対象外）
    private var personalAvg: [Double]? {
        let eligible = sessions
            .filter { $0.duration >= 300 && !$0.isExcludedFromAverage }
            .sorted { $0.date > $1.date }
            .prefix(5)
        guard eligible.count >= 2 else { return nil }
        let radars = eligible.map { s in
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
        let n = Double(eligible.count)
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
                    RadarLegendItem(color: .green, dashed: false, label: "直近5回平均")
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

struct RadarChartView: View {
    let values: [Double]
    let labels: [String]
    var valuesColor: Color = .blue
    var referenceA: [Double]? = nil
    var referenceAColor: Color = .gray
    var personalAvg: [Double]? = nil
    var personalAvgColor: Color = .green

    @State private var selectedAxisIndex: Int? = nil

    private struct AxisDetail {
        let maxLabel: String   // 軸端に常時表示するMAX値
        let maxFull: String    // ツールチップに表示する満点の説明
        let description: String
        let reference: String
    }

    private let axisDetails: [AxisDetail] = [
        AxisDetail(
            maxLabel: "130m/分",
            maxFull: "130m/分（分速130m＝時速7.8km）",
            description: "プレー中の総移動距離を時間で割った値。フィールドをどれだけ広くカバーできるかを示します。",
            reference: "アマ平均 80m/分"
        ),
        AxisDetail(
            maxLabel: "1.0回/分",
            maxFull: "1.0回/分（60分で60回のスプリント）",
            description: "時速20km/h以上のGPSポイントが2点以上続いた回数を時間で割った値。爆発的なダッシュ力を示します。",
            reference: "アマ平均 0.3回/分"
        ),
        AxisDetail(
            maxLabel: "4.5回/分",
            maxFull: "4.5回/分（60分で270回の方向転換）",
            description: "GPS軌跡で60度以上の方向転換を5.4km/h以上の速度で行った回数を時間で割った値。切り返しの敏捷性を示します。",
            reference: "アマ平均 2.0回/分"
        ),
        AxisDetail(
            maxLabel: "低下なし",
            maxFull: "後半の移動量 ÷ 前半の移動量 = 1.0（低下なし）",
            description: "後半の移動量が前半と比べてどれだけ維持できているかを示します。1.0が低下なし、値が低いほど後半に疲労が出ています。",
            reference: ""
        ),
        AxisDetail(
            maxLabel: "100%",
            maxFull: "最大心拍数の80%以上で動いた時間の割合（自分の頑張り度、100%が上限）",
            description: "最大心拍数の80%以上で動いた時間の割合。他人との比較ではなく、自分がどれだけ追い込めたかを示す指標です。心拍データが必要です。",
            reference: "アマ平均 30%"
        ),
        AxisDetail(
            maxLabel: "28.8km/h",
            maxFull: "28.8km/h",
            description: "セッション中にGPSで記録した最高速度。スプリント能力の上限を示します。",
            reference: "アマ平均 21.6km/h"
        ),
    ]

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
                    for level in stride(from: 0.25, through: 1.0, by: 0.25) {
                        let ring = hexagonPath(
                            vals: Array(repeating: Double(level), count: 6),
                            cx: cx, cy: cy, r: radius
                        )
                        ctx.stroke(ring, with: .color(.gray.opacity(0.25)), lineWidth: 1)
                    }
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
                    if let refA = referenceA {
                        let path = hexagonPath(vals: refA, cx: cx, cy: cy, r: radius)
                        ctx.stroke(path, with: .color(referenceAColor.opacity(0.65)),
                                   style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }
                    if let hist = personalAvg {
                        let path = hexagonPath(vals: hist, cx: cx, cy: cy, r: radius)
                        ctx.fill(path, with: .color(personalAvgColor.opacity(0.12)))
                        ctx.stroke(path, with: .color(personalAvgColor.opacity(0.65)), lineWidth: 1.5)
                    }
                    let dataPath = hexagonPath(vals: values, cx: cx, cy: cy, r: radius)
                    ctx.fill(dataPath, with: .color(valuesColor.opacity(0.25)))
                    ctx.stroke(dataPath, with: .color(valuesColor.opacity(0.75)), lineWidth: 2)
                }

                // タップ可能なラベル（軸名 + MAX値を常時表示）
                ForEach(0..<min(6, labels.count), id: \.self) { i in
                    let angle = -Double.pi / 2 + Double(i) * Double.pi / 3
                    let lr    = radius + 26
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedAxisIndex = selectedAxisIndex == i ? nil : i
                        }
                    } label: {
                        VStack(spacing: 1) {
                            Text(labels[i])
                                .font(.system(size: 10, weight: .medium))
                                .underline(selectedAxisIndex == i)
                                .foregroundStyle(selectedAxisIndex == i ? Color.blue : Color.primary)
                            if i < axisDetails.count {
                                Text(axisDetails[i].maxLabel)
                                    .font(.system(size: 8))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .multilineTextAlignment(.center)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: cx + CGFloat(cos(angle)) * lr,
                        y: cy + CGFloat(sin(angle)) * lr
                    )
                }

                // 説明ポップアップ
                if let idx = selectedAxisIndex, idx < axisDetails.count {
                    let detail = axisDetails[idx]
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                selectedAxisIndex = nil
                            }
                        }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(labels[idx])
                                .font(.subheadline.bold())
                            Spacer()
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    selectedAxisIndex = nil
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        HStack(spacing: 4) {
                            Text("満点（100%）")
                                .font(.caption2.bold())
                                .foregroundStyle(.orange)
                            Text(detail.maxFull)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 6)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(6)
                        Text(detail.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if !detail.reference.isEmpty {
                            HStack(spacing: 4) {
                                Text("アマ平均：")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.blue)
                                Text(detail.reference)
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.15), radius: 6)
                    .padding(.horizontal, 20)
                    .position(x: cx, y: cy)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
        }
    }
}

struct RadarLegendItem: View {
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
