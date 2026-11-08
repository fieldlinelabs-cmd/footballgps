//
//  CourtSwitchEditView.swift
//  FootballGPS
//
//  後半の入れ替えの指定画面（機能仕様書 §9.4）。前半と後半で陣地が入れ替わった試合で、
//  後半の開始位置を指定し、その後の動きだけを反転する。記録は1件のまま変わらない。
//

import SwiftUI

struct CourtSwitchEditView: View {
    let session: TrainingSession
    let gpsData: GPSData
    let field: Field
    let isFlipped: Bool

    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss

    /// 後半の開始位置（先頭点からの経過秒）
    @State private var switchOffset: TimeInterval

    /// 前半・後半それぞれに必要な最短の長さ（秒）
    static let minHalfDuration: TimeInterval = 60

    init(session: TrainingSession, gpsData: GPSData, field: Field, isFlipped: Bool) {
        self.session = session
        self.gpsData = gpsData
        self.field = field
        self.isFlipped = isFlipped

        // 設定済みならその位置、なければハーフタイムの候補から始める
        let total = Self.duration(of: gpsData)
        let start = gpsData.points.first?.timestamp ?? session.date
        let initial = session.courtSwitchDate?.timeIntervalSince(start)
            ?? DrillSplitDetector.suggestedCourtSwitchOffset(
                breaks: DrillSplitDetector.detectBreaks(points: gpsData.points, field: field),
                totalDuration: total
            )
        _switchOffset = State(initialValue: min(max(Self.minHalfDuration, initial), total - Self.minHalfDuration))
    }

    private static func duration(of gpsData: GPSData) -> TimeInterval {
        guard let first = gpsData.points.first, let last = gpsData.points.last else { return 0 }
        return last.timestamp.timeIntervalSince(first.timestamp)
    }

    private var totalDuration: TimeInterval { Self.duration(of: gpsData) }

    private var switchDate: Date? {
        gpsData.points.first?.timestamp.addingTimeInterval(switchOffset)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("前半と後半で陣地が入れ替わった試合で、後半が始まった位置を指定します。後半の動きだけを反転して、前半と同じ向きにそろえます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                DrillSplitFieldMapView(
                    gpsData: gpsData,
                    field: field,
                    orientation: CourtOrientation(isFlipped: isFlipped, switchDate: switchDate),
                    ranges: [(0, switchOffset), (switchOffset, totalDuration)],
                    breaks: []
                )
                .frame(height: 340)

                legend
                timeline
                scrubControls
            }
            .padding()
        }
        .navigationTitle("前後半を設定")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button("キャンセル") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                if session.courtSwitchDate != nil {
                    Button("解除", role: .destructive) {
                        save(nil)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    save(switchDate)
                } label: {
                    Text("保存する")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem(color: DrillSplitFieldMapView.segmentColors[0], label: "前半 \(formatElapsed(switchOffset))")
            legendItem(color: DrillSplitFieldMapView.segmentColors[1], label: "後半 \(formatElapsed(totalDuration - switchOffset))")
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Timeline

    /// 記録全体を1本のバーで表し、前半・後半で色分けする。タップ・ドラッグで位置を動かせる
    private var timeline: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let switchX = totalDuration > 0 ? width * CGFloat(switchOffset / totalDuration) : 0
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DrillSplitFieldMapView.segmentColors[1])
                Rectangle()
                    .fill(DrillSplitFieldMapView.segmentColors[0])
                    .frame(width: max(0, switchX))
                Rectangle()
                    .fill(Color.primary)
                    .frame(width: 2)
                    .offset(x: switchX - 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        moveSwitch(to: value.location.x / width * totalDuration)
                    }
            )
        }
        .frame(height: 32)
        .padding(.vertical, 4)
    }

    private var scrubControls: some View {
        HStack(spacing: 8) {
            Button("−1分") { moveSwitch(to: switchOffset - 60) }
            Button("−5秒") { moveSwitch(to: switchOffset - 5) }

            Spacer(minLength: 0)
            Text(formatElapsed(switchOffset))
                .font(.subheadline.monospacedDigit())
            Spacer(minLength: 0)

            Button("＋5秒") { moveSwitch(to: switchOffset + 5) }
            Button("＋1分") { moveSwitch(to: switchOffset + 60) }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Actions

    private func moveSwitch(to offset: TimeInterval) {
        switchOffset = min(max(Self.minHalfDuration, offset), totalDuration - Self.minHalfDuration)
    }

    private func save(_ date: Date?) {
        dataManager.updateCourtSwitchDate(for: session.id, date: date)
        dismiss()
    }

    private func formatElapsed(_ time: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
    }
}
