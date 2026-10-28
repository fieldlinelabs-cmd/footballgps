//
//  DrillSplitManualEditView.swift
//  FootballGPS
//
//  ドリルの手動切り出し画面（docs/手動ドリル分割仕様書.md）。
//  再生位置で区切りを追加し、区切られた区間ごとに「ドリル／休憩」を切り替えて、
//  1本以上のドリルを切り出す。確定処理は自動分割と共通（SessionDataManager.applyDrillSplit）。
//

import SwiftUI

struct DrillSplitManualEditView: View {
    let session: TrainingSession
    let gpsData: GPSData
    let field: Field
    let isFlipped: Bool
    /// 確定後に呼ばれる（呼び出し元の画面を閉じるため）
    let onConfirmed: () -> Void

    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss

    /// 区切り位置（先頭点からの経過秒、昇順、0 と末尾は含まない）
    @State private var cutOffsets: [TimeInterval]
    /// 区間ごとのドリル/休憩（要素数 = cutOffsets.count + 1）
    @State private var isDrill: [Bool]
    @State private var currentTime: TimeInterval = 0
    /// 区間ごとの指標（区切りが変わるたびに再計算する。算出できない区間は nil）
    @State private var segmentStats: [SessionDataManager.SegmentStats?] = []
    @State private var showConfirm = false
    @State private var isConfirming = false

    /// 区切り同士・先頭・末尾との最小間隔（秒）
    private static let minCutGap: TimeInterval = 5

    init(
        session: TrainingSession,
        gpsData: GPSData,
        field: Field,
        isFlipped: Bool,
        initialRanges: [(start: TimeInterval, end: TimeInterval)],
        onConfirmed: @escaping () -> Void
    ) {
        self.session = session
        self.gpsData = gpsData
        self.field = field
        self.isFlipped = isFlipped
        self.onConfirmed = onConfirmed

        // 自動検出の候補があればそれを初期状態にし、なければ全体を1本のドリルにする
        let total = Self.duration(of: gpsData)
        if initialRanges.isEmpty {
            _cutOffsets = State(initialValue: [])
            _isDrill = State(initialValue: [true])
        } else {
            let state = DrillSplitDetector.manualState(fromDrillRanges: initialRanges, totalDuration: total)
            _cutOffsets = State(initialValue: state.cutOffsets)
            _isDrill = State(initialValue: state.isDrill)
        }
    }

    private static func duration(of gpsData: GPSData) -> TimeInterval {
        guard let first = gpsData.points.first, let last = gpsData.points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    private var totalDuration: TimeInterval { Self.duration(of: gpsData) }

    private var segments: [(start: TimeInterval, end: TimeInterval)] {
        DrillSplitDetector.segments(cutOffsets: cutOffsets, totalDuration: totalDuration)
    }

    private var drillRanges: [(start: TimeInterval, end: TimeInterval)] {
        DrillSplitDetector.manualRanges(cutOffsets: cutOffsets, isDrill: isDrill, totalDuration: totalDuration)
    }

    /// 地図にグレーの破線で描く休憩区間
    private var restIntervals: [DrillBreakInterval] {
        zip(segments, isDrill)
            .filter { !$0.1 }
            .map { DrillBreakInterval(startOffset: $0.0.start, endOffset: $0.0.end) }
    }

    /// index 番目の区間がドリルなら、その通し番号（0始まり）。休憩なら nil
    private func drillNumber(ofSegment index: Int) -> Int? {
        guard isDrill.indices.contains(index), isDrill[index] else { return nil }
        return isDrill[..<index].filter { $0 }.count
    }

    private func color(ofSegment index: Int) -> Color {
        guard let number = drillNumber(ofSegment: index) else { return Color.gray.opacity(0.4) }
        return DrillSplitFieldMapView.segmentColors[number % DrillSplitFieldMapView.segmentColors.count]
    }

    /// ドリルとして短すぎる（60秒未満、または点が少なく指標を算出できない）か
    private func isTooShort(segment index: Int) -> Bool {
        let segment = segments[index]
        if segment.end - segment.start < DrillSplitConfig.minSegmentDuration { return true }
        guard segmentStats.indices.contains(index) else { return false }
        return segmentStats[index] == nil
    }

    /// 確定できない理由（確定できるなら nil）
    private var validationMessage: String? {
        if drillRanges.isEmpty {
            return "ドリルを1本以上選んでください"
        }
        if cutOffsets.isEmpty {
            return "「ここで区切る」で区切りを追加し、残す範囲を指定してください"
        }
        if segments.indices.contains(where: { isDrill[$0] && isTooShort(segment: $0) }) {
            return "60秒未満のドリルがあります。休憩にするか、区切りを削除してください"
        }
        return nil
    }

    private var canAddCut: Bool {
        currentTime >= Self.minCutGap
            && currentTime <= totalDuration - Self.minCutGap
            && !cutOffsets.contains { abs($0 - currentTime) < Self.minCutGap }
    }

    var body: some View {
        // 上部（地図・タイムライン・操作）は固定し、区間の一覧だけをスクロールさせる。
        // 全体を1つのListにすると、地図とタイムラインの分だけ一覧が画面外・下部ボタンの裏に隠れるため
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                DrillSplitFieldMapView(
                    gpsData: gpsData,
                    field: field,
                    isFlipped: isFlipped,
                    ranges: drillRanges,
                    breaks: restIntervals,
                    currentOffset: currentTime
                )
                .frame(height: 180)

                timeline
                scrubControls
            }
            .padding(.horizontal)
            .padding(.top, 8)

            List {
                Section {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        segmentRow(index: index, segment: segment)
                            .swipeActions(edge: .trailing) {
                                if index > 0 {
                                    Button("左の区切りを削除", role: .destructive) {
                                        removeCut(at: index - 1)
                                    }
                                }
                            }
                    }
                } header: {
                    Text("区間（右のスイッチでドリル／休憩を切り替え）")
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("ドリルを切り出す")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button("キャンセル") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isConfirming)

                    Button {
                        showConfirm = true
                    } label: {
                        Text("\(drillRanges.count)本のドリルを切り出す")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(validationMessage != nil || isConfirming)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .overlay {
            if isConfirming {
                ProgressView("切り出し中…")
                    .padding()
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .confirmationDialog(
            drillRanges.count == 1 ? "ドリルを切り出しますか？" : "\(drillRanges.count)本のドリルに分割しますか？",
            isPresented: $showConfirm,
            titleVisibility: .visible
        ) {
            Button(drillRanges.count == 1 ? "切り出す" : "分割する") {
                confirm()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text(confirmMessage)
        }
        .onAppear(perform: recomputeStats)
        .onChange(of: cutOffsets) { _, _ in recomputeStats() }
    }

    // MARK: - Timeline

    /// 記録全体を1本のバーで表し、区間ごとに色分けする。タップ・ドラッグで再生位置を動かせる
    private var timeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Rectangle()
                        .fill(color(ofSegment: index))
                        .frame(width: max(0, width * fraction(segment.end - segment.start)))
                        .offset(x: width * fraction(segment.start))
                }
                ForEach(cutOffsets, id: \.self) { cut in
                    Rectangle()
                        .fill(Color.primary)
                        .frame(width: 2)
                        .offset(x: width * fraction(cut) - 1)
                }
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 2)
                    .offset(x: width * fraction(currentTime) - 1)
            }
            .frame(height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        currentTime = min(max(0, value.location.x / width), 1) * totalDuration
                    }
            )
        }
        .frame(height: 32)
        .padding(.vertical, 4)
    }

    private func fraction(_ offset: TimeInterval) -> CGFloat {
        totalDuration > 0 ? CGFloat(offset / totalDuration) : 0
    }

    private var scrubControls: some View {
        VStack(spacing: 8) {
            Slider(value: $currentTime, in: 0...max(totalDuration, 1))

            HStack(spacing: 8) {
                Button {
                    currentTime = max(0, currentTime - 5)
                } label: {
                    Text("−5秒")
                }
                .buttonStyle(.bordered)

                Button {
                    currentTime = min(totalDuration, currentTime + 5)
                } label: {
                    Text("＋5秒")
                }
                .buttonStyle(.bordered)

                Text(formatElapsed(currentTime))
                    .font(.subheadline.monospacedDigit())

                Spacer(minLength: 0)

                Button {
                    addCut(at: currentTime)
                } label: {
                    Label("ここで区切る", systemImage: "scissors")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!canAddCut)
            }
            .controlSize(.small)
        }
    }

    // MARK: - Segment Row

    private func segmentRow(index: Int, segment: (start: TimeInterval, end: TimeInterval)) -> some View {
        HStack(spacing: 10) {
            Button {
                currentTime = segment.start
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(color(ofSegment: index))
                        .frame(width: 10, height: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(drillNumber(ofSegment: index).map { "ドリル\($0 + 1)" } ?? "休憩")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(formatRange(segment) + distanceText(index: index))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isDrill[index] && isTooShort(segment: index) {
                            Text("短すぎます（60秒以上）")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Toggle("ドリル", isOn: Binding(
                get: { isDrill[index] },
                set: { isDrill[index] = $0 }
            ))
            .labelsHidden()
        }
    }

    private func distanceText(index: Int) -> String {
        guard segmentStats.indices.contains(index), let stats = segmentStats[index] else { return "" }
        return "・" + formatDistance(stats.totalDistance)
    }

    // MARK: - Actions

    private func addCut(at offset: TimeInterval) {
        guard canAddCut else { return }
        // 区切る区間の種別を、分かれた前後の両方に引き継ぐ
        let segmentIndex = cutOffsets.filter { $0 < offset }.count
        cutOffsets.insert(offset, at: segmentIndex)
        isDrill.insert(isDrill[segmentIndex], at: segmentIndex + 1)
    }

    /// cutIndex 番目の区切りを削除し、前後の区間を1つにする（左側の区間の種別を残す）
    private func removeCut(at cutIndex: Int) {
        guard cutOffsets.indices.contains(cutIndex) else { return }
        cutOffsets.remove(at: cutIndex)
        isDrill.remove(at: cutIndex + 1)
    }

    private func recomputeStats() {
        segmentStats = segments.map { segment in
            SessionDataManager.computeSegmentStats(
                points: SessionDataManager.slicedPoints(gpsData.points, from: segment.start, to: segment.end)
            )
        }
    }

    private func confirm() {
        let ranges = drillRanges
        isConfirming = true
        Task {
            await dataManager.applyDrillSplit(for: session.id, ranges: ranges)
            isConfirming = false
            onConfirmed()
        }
    }

    // MARK: - Formatting

    private var confirmMessage: String {
        let restoreNote = "分割前の記録は「分割前の記録に戻す」でいつでも復元できます。"
        guard drillRanges.count == 1,
              let index = segments.indices.first(where: { isDrill[$0] }),
              segmentStats.indices.contains(index),
              let stats = segmentStats[index] else {
            return restoreNote
        }
        return "時間: \(formatElapsed(session.duration)) → \(formatElapsed(stats.duration))\n"
            + "距離: \(formatDistance(session.totalDistance)) → \(formatDistance(stats.totalDistance))\n"
            + restoreNote
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }

    private func formatRange(_ range: (start: TimeInterval, end: TimeInterval)) -> String {
        let duration = range.end - range.start
        let startTime = session.date.addingTimeInterval(range.start)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return "\(formatter.string(from: startTime))〜 (\(Int(duration) / 60)分\(Int(duration) % 60)秒)"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters >= 1000 {
            return String(format: "%.2f km", meters / 1000)
        } else {
            return String(format: "%.0f m", meters)
        }
    }
}
