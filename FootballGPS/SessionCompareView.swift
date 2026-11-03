//
//  SessionCompareView.swift
//  FootballGPS
//
//  2回のセッションを左右に並べて見る画面（機能仕様書 §9.6）。
//  差は相手や味方など記録に残らない条件に左右されるので、差分や良し悪しの判定は出さず、
//  同じ形で並べて、考察はユーザーに任せる。
//

import SwiftUI

struct SessionCompareView: View {
    let session: TrainingSession
    let gpsData: GPSData
    /// 比較先の候補（新しい順）
    let candidates: [TrainingSession]

    @State private var comparison: TrainingSession
    @State private var comparisonGPS: GPSData?
    @State private var showingPicker = false
    /// 振り返りを書いているセッション。書いている間も、裏の比較画面を見られる
    @State private var reflectionTarget: TrainingSession?
    @ObservedObject private var fieldManager = FieldManager.shared
    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss

    init(session: TrainingSession, gpsData: GPSData, candidates: [TrainingSession], initialComparison: TrainingSession) {
        self.session = session
        self.gpsData = gpsData
        self.candidates = candidates
        _comparison = State(initialValue: initialComparison)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    header(session)
                        .frame(maxWidth: .infinity)
                    Button {
                        showingPicker = true
                    } label: {
                        header(comparison, showsChevron: true)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .disabled(reflectionTarget != nil)
                }

                HStack(spacing: 0) {
                    heatmap(session: session, gpsData: gpsData)
                    heatmap(session: comparison, gpsData: comparisonGPS)
                }
                .padding(.horizontal, -8)

                // 差が出た理由を考える材料として、書いた振り返りも並べる（機能仕様書 §9.7）
                HStack(alignment: .top, spacing: 12) {
                    reflectionSummary(session)
                    reflectionSummary(comparison)
                }

                VStack(spacing: 0) {
                    row("時間", formatDuration(session.duration), formatDuration(comparison.duration))
                    row("総距離", formatDistance(session.totalDistance), formatDistance(comparison.totalDistance))
                    ForEach(GrowthTrendEngine.Metric.allCases) { metric in
                        row(metric.label, metricText(metric, session), metricText(metric, comparison))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("2回を比べる")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
                .disabled(reflectionTarget != nil)
            }
        }
        .task(id: comparison.id) {
            comparisonGPS = dataManager.getGPSData(for: comparison.id)
        }
        .sheet(item: $reflectionTarget) { target in
            SessionReflectionSheet(session: latest(target))
                .id(target.id)
        }
        .sheet(isPresented: $showingPicker) {
            NavigationStack {
                CompareSessionPickerView(candidates: candidates, selectedId: comparison.id) { selected in
                    comparison = selected
                    showingPicker = false
                }
            }
        }
    }

    // MARK: - Parts

    /// 保存した振り返りをすぐ反映するため、最新の状態を読む
    private func latest(_ session: TrainingSession) -> TrainingSession {
        dataManager.sessions.first { $0.id == session.id } ?? session
    }

    private func reflectionSummary(_ session: TrainingSession) -> some View {
        // 書いている間に反対側を押すと、シートの内容と書き込み先がずれるので押せなくする
        SessionReflectionSummary(
            reflection: latest(session).reflection,
            isEditing: reflectionTarget?.id == session.id
        ) {
            reflectionTarget = session
        }
        .disabled(reflectionTarget != nil)
    }

    private func header(_ session: TrainingSession, showsChevron: Bool = false) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Text(CompareSessionText.date(session))
                    .font(.subheadline.bold())
                if showsChevron {
                    Image(systemName: "chevron.down")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                }
            }
            Text(CompareSessionText.detail(session, fieldName: fieldName(of: session)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if session.isLowGPSAccuracy {
                Text("GPS精度が低い記録")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func heatmap(session: TrainingSession, gpsData: GPSData?) -> some View {
        if let gpsData, let field = session.fieldId.flatMap({ fieldManager.getField(by: $0) }) {
            FieldHeatmapView(gpsData: gpsData, field: field, orientation: session.courtOrientation)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
        } else {
            Text("ヒートマップを表示できません")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 320)
        }
    }

    private func row(_ label: String, _ left: String, _ right: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(left)
                    .frame(maxWidth: .infinity)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 76)
                Text(right)
                    .frame(maxWidth: .infinity)
            }
            .font(.subheadline.monospacedDigit())
            .padding(.vertical, 8)
            Divider()
        }
    }

    // MARK: - Formatting

    private func fieldName(of session: TrainingSession) -> String? {
        session.fieldId.flatMap { fieldManager.getField(by: $0) }?.name
    }

    private func metricText(_ metric: GrowthTrendEngine.Metric, _ session: TrainingSession) -> String {
        guard let value = metric.value(for: session) else { return "--" }
        let text = "\(metric.format(value)) \(metric.unit)"
        return metric.isReferenceOnly(session) ? "\(text)（参考値）" : text
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

// MARK: - 比較先の一覧

private struct CompareSessionPickerView: View {
    let candidates: [TrainingSession]
    let selectedId: String
    let onSelect: (TrainingSession) -> Void

    @ObservedObject private var fieldManager = FieldManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(candidates) { candidate in
            Button {
                onSelect(candidate)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(CompareSessionText.date(candidate))
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(subtitle(candidate))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if candidate.isLowGPSAccuracy {
                            Text("GPS精度が低い記録")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if candidate.id == selectedId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("比較するセッション")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    dismiss()
                }
            }
        }
    }

    private func subtitle(_ candidate: TrainingSession) -> String {
        let fieldName = candidate.fieldId.flatMap { fieldManager.getField(by: $0) }?.name
        return "\(CompareSessionText.detail(candidate, fieldName: fieldName))・\(Int(candidate.duration) / 60)分"
    }
}

/// 比較画面と一覧で共有する表記
private enum CompareSessionText {
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d HH:mm"
        return formatter
    }()

    static func date(_ session: TrainingSession) -> String {
        dateFormatter.string(from: session.date)
    }

    static func detail(_ session: TrainingSession, fieldName: String?) -> String {
        [session.position?.displayName ?? "ポジション未設定", fieldName]
            .compactMap { $0 }
            .joined(separator: "・")
    }
}
