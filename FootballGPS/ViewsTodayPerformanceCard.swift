//
//  ViewsTodayPerformanceCard.swift
//  FootballGPS
//
//  セッション詳細の「ポジション」チップ・選択シート（docs/統計推移仕様書.md §4.3）と
//  「今日の出来」カード（§9）。計算は GrowthTrendEngine に集約する。

import SwiftUI

// MARK: - ポジションのチップ

struct PositionChip: View {
    let session: TrainingSession
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "figure.soccer")
                    .font(.caption2)
                Text("ポジション: \(label)")
                    .font(.caption.bold())
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.12))
            .foregroundStyle(Color.accentColor)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var label: String {
        guard let position = session.position else { return "未設定" }
        return session.positionSource == .manual ? position.displayName : "\(position.displayName)（自動）"
    }
}

// MARK: - ポジションの選択シート

struct PositionPickerSheet: View {
    let session: TrainingSession
    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(PlayingPosition.allCases) { position in
                        Button {
                            dataManager.setManualPosition(for: session.id, position: position)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(position.displayName)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                    Text(position.includedRoles)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if session.position == position && session.positionSource == .manual {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("WB はヒートマップでは SB・WG と見分けられないため、自動推定では SB か WG になります。一度 WB に直すと、それ以降のセッションの SB・WG の推定は WB として扱います。")
                }

                Section {
                    Button("自動推定に戻す") {
                        dataManager.resetPositionToAuto(for: session.id)
                        dismiss()
                    }
                    .disabled(session.positionSource != .manual)
                } footer: {
                    Text(autoFooter)
                }
            }
            .navigationTitle("ポジション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var autoFooter: String {
        if let estimated = session.estimatedPosition {
            return "自動推定の結果: \(estimated.displayName)（ヒートマップから推定）"
        }
        return "フィールドが紐付いていないか記録が短いため、自動推定できません"
    }
}

// MARK: - 今日の出来カード

struct TodayPerformanceCard: View {
    let session: TrainingSession
    let sessions: [TrainingSession]

    @AppStorage("todayPerformance.period") private var periodRaw = GrowthTrendEngine.Period.threeMonths.rawValue

    private var period: GrowthTrendEngine.Period {
        GrowthTrendEngine.Period(rawValue: periodRaw) ?? .threeMonths
    }

    private var isEligible: Bool {
        !PlayerDataEngine.eligibleSessions([session]).isEmpty
    }

    private var comparisons: [TrainingSession] {
        GrowthTrendEngine.comparisonSessions(for: session, in: sessions, period: period)
    }

    var body: some View {
        if isEligible {
            let comparisons = comparisons
            VStack(alignment: .leading, spacing: 10) {
                Text("今日の出来")
                    .font(.headline)
                Text("\(period.longLabel)・\(session.position?.displayName ?? "全ポジション")・比較\(comparisons.count)回")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Picker("期間", selection: $periodRaw) {
                    ForEach(GrowthTrendEngine.Period.allCases) { p in
                        Text(p.label).tag(p.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                ForEach(GrowthTrendEngine.Metric.allCases) { metric in
                    TodayMetricRow(
                        metric: metric,
                        currentValue: metric.value(for: session),
                        comparison: GrowthTrendEngine.todayComparison(target: session, comparisons: comparisons, metric: metric)
                    )
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

private struct TodayMetricRow: View {
    let metric: GrowthTrendEngine.Metric
    let currentValue: Double?
    let comparison: GrowthTrendEngine.TodayComparison?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(metric.label)
                    .font(.caption)
                    .frame(width: 72, alignment: .leading)
                Text(currentValue.map { "\(metric.format($0)) \(metric.unit)" } ?? "--")
                    .font(.subheadline.bold())
                    .monospacedDigit()
                Spacer()
                if let comparison {
                    if metric.hasDirection {
                        if let pct = comparison.percentFromAverage {
                            ChangeBadge(text: String(format: "平均比 %+.0f%%", pct), isPositive: pct >= 0)
                        }
                        Text("\(comparison.total)回中 \(comparison.rank)位")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(heightFromAverageText(comparison.differenceFromAverage))
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                    }
                } else if currentValue != nil {
                    Text("データ不足")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let comparison, metric.hasDirection {
                DistributionBar(comparison: comparison)
                    .frame(height: 10)
                    .padding(.leading, 72)
            }
        }
    }
}

/// 「高さ」の平均との差の表示（良し悪しの色は付けない、§6.4）
private func heightFromAverageText(_ difference: Double) -> String {
    let rounded = Int(difference.rounded())
    if rounded == 0 { return "平均とほぼ同じ" }
    return rounded > 0 ? "平均より\(rounded)ポイント前" : "平均より\(-rounded)ポイント後ろ"
}

/// 比較対象の最小〜最大（線）・25〜75パーセンタイル（帯）・今回の値（マーカー）
private struct DistributionBar: View {
    let comparison: GrowthTrendEngine.TodayComparison

    var body: some View {
        GeometryReader { geo in
            let lo = Swift.min(comparison.min, comparison.value)
            let hi = Swift.max(comparison.max, comparison.value)
            let span = Swift.max(hi - lo, 0.0001)
            let x: (Double) -> CGFloat = { CGFloat(($0 - lo) / span) * geo.size.width }
            let midY = geo.size.height / 2

            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(width: x(comparison.max) - x(comparison.min), height: 2)
                    .offset(x: x(comparison.min), y: midY - 1)
                Capsule()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: Swift.max(x(comparison.p75) - x(comparison.p25), 2), height: 6)
                    .offset(x: x(comparison.p25), y: midY - 3)
                Circle()
                    .fill(Color.blue)
                    .overlay(Circle().stroke(Color(.systemGray6), lineWidth: 2))
                    .frame(width: 10, height: 10)
                    .offset(x: x(comparison.value) - 5, y: midY - 5)
            }
        }
    }
}
