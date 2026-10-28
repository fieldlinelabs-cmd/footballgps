//
//  ViewsGrowthTrendView.swift
//  FootballGPS
//
//  Stats タブ（推移画面、docs/統計推移仕様書.md §8）と、直近5回平均との比較カード。
//  計算は GrowthTrendEngine・PlayerDataEngine に集約し、このファイルは表示のみを担当する。

import SwiftUI
import Charts

/// Stats タブのルート
struct StatsView: View {
    var body: some View {
        NavigationStack {
            GrowthTrendView()
        }
    }
}

struct GrowthTrendView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared

    @AppStorage("growthTrend.period") private var periodRaw = GrowthTrendEngine.Period.threeMonths.rawValue
    @AppStorage("growthTrend.position") private var positionRaw = GrowthTrendEngine.PositionFilter.all.rawValue
    @AppStorage("growthTrend.metric") private var metricRaw = GrowthTrendEngine.Metric.distance.rawValue

    @State private var selectedPointId: String?

    private var period: GrowthTrendEngine.Period {
        GrowthTrendEngine.Period(rawValue: periodRaw) ?? .threeMonths
    }
    private var position: GrowthTrendEngine.PositionFilter {
        GrowthTrendEngine.PositionFilter(rawValue: positionRaw)
    }
    private var metric: GrowthTrendEngine.Metric {
        GrowthTrendEngine.Metric(rawValue: metricRaw) ?? .distance
    }

    private var sessionsInPeriod: [TrainingSession] {
        GrowthTrendEngine.filteredSessions(dataManager.sessions, period: period, position: position, reference: Date())
    }

    private var points: [GrowthTrendEngine.TrendPoint] {
        GrowthTrendEngine.trendPoints(sessions: dataManager.sessions, metric: metric, period: period, position: position)
    }

    /// 全期間の自己ベスト（期間の外でも点線で示す）
    private var personalBest: GrowthTrendEngine.PersonalBest? {
        GrowthTrendEngine.personalBest(sessions: dataManager.sessions, metric: metric, position: position, until: Date())
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                RecentComparisonCard(sessions: dataManager.sessions)
                filterControls
                chartCard
                summaryCard
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Stats")
        .onChange(of: periodRaw) { _, _ in selectedPointId = nil }
        .onChange(of: positionRaw) { _, _ in selectedPointId = nil }
        .onChange(of: metricRaw) { _, _ in selectedPointId = nil }
    }

    // MARK: - 絞り込み

    private var filterControls: some View {
        VStack(spacing: 10) {
            Picker("期間", selection: $periodRaw) {
                ForEach(GrowthTrendEngine.Period.allCases) { p in
                    Text(p.label).tag(p.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Text("ポジション")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(GrowthTrendEngine.PositionFilter.allCases) { filter in
                        let count = countInPeriod(filter)
                        Button {
                            positionRaw = filter.rawValue
                        } label: {
                            if filter == position {
                                Label("\(filter.label)（\(count)回）", systemImage: "checkmark")
                            } else {
                                Text("\(filter.label)（\(count)回）")
                            }
                        }
                        .disabled(count == 0 && filter != .all)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(position.label)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .font(.subheadline.bold())
                }
            }
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GrowthTrendEngine.Metric.allCases) { m in
                        Button {
                            metricRaw = m.rawValue
                        } label: {
                            Text(m.label)
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(m == metric ? Color.accentColor : Color(.systemGray5))
                                .foregroundStyle(m == metric ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func countInPeriod(_ filter: GrowthTrendEngine.PositionFilter) -> Int {
        GrowthTrendEngine.filteredSessions(dataManager.sessions, period: period, position: filter, reference: Date()).count
    }

    // MARK: - 推移グラフ

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(metric.detailLabel)（\(metric.unit)）")
                .font(.subheadline.bold())

            if points.isEmpty {
                Text("この条件のセッションはまだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                TrendChart(points: points, metric: metric, personalBest: personalBest, selectedPointId: $selectedPointId)
                    .frame(height: 240)
                legend
                if metric == .height {
                    Text("自陣のゴールラインを0%、敵陣のゴールラインを100%として、フィールドの縦方向のどこでプレーしていたかを表します。50%がセンターラインです。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let id = selectedPointId, let point = points.first(where: { $0.id == id }) {
                    selectedPointDetail(point)
                } else {
                    Text("点をタップすると詳細を表示します")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    @ViewBuilder
    private var legend: some View {
        HStack(spacing: 14) {
            if metric == .height {
                TrendLegendItem(symbol: .circle, color: .blue, label: "平均の高さ")
                TrendLegendItem(symbol: .triangle, color: .orange, label: "最前線の高さ")
                TrendLegendItem(symbol: .square, color: .green, label: "最低線の高さ")
            } else {
                TrendLegendItem(symbol: .circle, color: .blue, label: "各セッション")
                TrendLegendItem(symbol: .line, color: .blue, label: "直近\(GrowthTrendEngine.movingAverageWindow)回の平均")
                TrendLegendItem(symbol: .star, color: .orange, label: "自己ベスト")
            }
        }
        .font(.caption2)
    }

    @ViewBuilder
    private func selectedPointDetail(_ point: GrowthTrendEngine.TrendPoint) -> some View {
        if let session = dataManager.sessions.first(where: { $0.id == point.sessionId }),
           let gpsData = dataManager.getGPSData(for: session.id) {
            NavigationLink {
                SessionDetailView(session: session, gpsData: gpsData)
            } label: {
                selectedPointLabel(point, session: session)
            }
            .buttonStyle(.plain)
        } else if let session = dataManager.sessions.first(where: { $0.id == point.sessionId }) {
            selectedPointLabel(point, session: session)
        }
    }

    private func selectedPointLabel(_ point: GrowthTrendEngine.TrendPoint, session: TrainingSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                    .font(.caption.bold())
                Text("\(point.date.formatted(date: .abbreviated, time: .shortened)) ・ \(formatDuration(point.duration))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if metric == .height {
                    Text("平均 \(metric.format(point.value))%")
                        .font(.caption.bold())
                    if let front = point.frontHeight {
                        Text("最前線 \(metric.format(front))%")
                            .font(.caption2)
                    }
                    if let back = point.backHeight {
                        Text("最低線 \(metric.format(back))%")
                            .font(.caption2)
                    }
                } else {
                    Text("\(metric.format(point.value)) \(metric.unit)")
                        .font(.caption.bold())
                    if point.isPersonalBest {
                        Text("自己ベスト")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    // MARK: - 成長サマリー

    private var summaryCard: some View {
        let sessions = sessionsInPeriod
        return VStack(alignment: .leading, spacing: 10) {
            Text("成長サマリー（\(period.longLabel)・\(position.label)・\(sessions.count)回）")
                .font(.subheadline.bold())
            Text("期間内のセッションを前半と後半に分けて平均を比べます")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if sessions.count < GrowthTrendEngine.halfComparisonMinSessions {
                Text("\(GrowthTrendEngine.halfComparisonMinSessions)回以上の記録が貯まると表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(GrowthTrendEngine.Metric.allCases) { m in
                    summaryRow(metric: m, comparison: GrowthTrendEngine.halfComparison(sessionsInPeriod: sessions, metric: m))
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func summaryRow(metric m: GrowthTrendEngine.Metric, comparison: GrowthTrendEngine.HalfComparison?) -> some View {
        HStack {
            Text(m.label)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            if let comparison {
                Text("\(m.format(comparison.firstAverage)) → \(m.format(comparison.secondAverage)) \(m.unit)")
                    .font(.caption)
                    .monospacedDigit()
                Spacer()
                if m.hasDirection {
                    if let change = comparison.percentChange {
                        ChangeBadge(text: String(format: "%+.0f%%", change), isPositive: change >= 0)
                    }
                } else {
                    Text(heightDifferenceText(comparison.difference))
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }
}

/// 「高さ」の差分の表示（良し悪しの色は付けない、§6.4）
func heightDifferenceText(_ difference: Double) -> String {
    let rounded = Int(difference.rounded())
    if rounded == 0 { return "ほぼ同じ" }
    return rounded > 0 ? "\(rounded)ポイント前へ" : "\(-rounded)ポイント後ろへ"
}

/// 増減のバッジ（比較カードと同じ緑・オレンジ）。符号付きの数値と一緒に出すので色だけに頼らない
struct ChangeBadge: View {
    let text: String
    let isPositive: Bool

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(isPositive ? Color.green : Color.orange)
            .foregroundStyle(.white)
            .clipShape(Capsule())
    }
}

// MARK: - 推移グラフ本体

private struct TrendChart: View {
    let points: [GrowthTrendEngine.TrendPoint]
    let metric: GrowthTrendEngine.Metric
    let personalBest: GrowthTrendEngine.PersonalBest?
    @Binding var selectedPointId: String?

    @State private var rawSelectedDate: Date?

    var body: some View {
        Chart {
            ForEach(points) { point in
                if metric == .height {
                    PointMark(x: .value("日付", point.date), y: .value("平均の高さ", point.value))
                        .symbol(.circle)
                        .symbolSize(point.id == selectedPointId ? 110 : 60)
                        .foregroundStyle(.blue)
                    if let front = point.frontHeight {
                        PointMark(x: .value("日付", point.date), y: .value("最前線の高さ", front))
                            .symbol(.triangle)
                            .symbolSize(point.id == selectedPointId ? 110 : 60)
                            .foregroundStyle(.orange)
                    }
                    if let back = point.backHeight {
                        PointMark(x: .value("日付", point.date), y: .value("最低線の高さ", back))
                            .symbol(.square)
                            .symbolSize(point.id == selectedPointId ? 110 : 60)
                            .foregroundStyle(.green)
                    }
                } else {
                    PointMark(x: .value("日付", point.date), y: .value(metric.label, point.value))
                        .symbol(point.isPersonalBest ? BasicChartSymbolShape.asterisk : BasicChartSymbolShape.circle)
                        .symbolSize(point.id == selectedPointId ? 130 : (point.isPersonalBest ? 110 : 60))
                        .foregroundStyle(point.isPersonalBest ? Color.orange : Color.blue.opacity(0.55))
                }
            }

            if metric != .height {
                ForEach(points.filter { $0.movingAverage != nil }) { point in
                    LineMark(x: .value("日付", point.date), y: .value("移動平均", point.movingAverage ?? 0))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .foregroundStyle(.blue)
                }
            }

            if let best = personalBest {
                // 自己ベストの値。期間の外の記録でも、どこが自分のベストか分かるように常に示す
                RuleMark(y: .value("自己ベスト", best.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.orange.opacity(0.8))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("自己ベスト \(metric.format(best.value))（\(best.date.formatted(.dateTime.month().day()))）")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
            }

            if let id = selectedPointId, let selected = points.first(where: { $0.id == id }) {
                RuleMark(x: .value("日付", selected.date))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(.secondary)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $rawSelectedDate)
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine().foregroundStyle(Color(.systemGray4))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(metric.format(v)).font(.system(size: 10))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month().day()).font(.system(size: 10))
            }
        }
        .onChange(of: rawSelectedDate) { _, date in
            guard let date else { return }
            // タップ位置に最も近い日付の点を選ぶ（マークより広い範囲で拾う）
            selectedPointId = points.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            })?.id
        }
    }

    /// 値の範囲に少し余白を取る。「高さ」は 0〜100% 固定
    private var yDomain: ClosedRange<Double> {
        if metric == .height { return 0...100 }
        // 自己ベストの点線が範囲外に出ないよう、その値も含める
        let values = points.map(\.value) + [personalBest?.value].compactMap { $0 }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = Swift.max((hi - lo) * 0.15, Swift.max(abs(hi) * 0.05, 0.5))
        return Swift.max(0, lo - pad)...(hi + pad)
    }
}

private struct TrendLegendItem: View {
    enum Symbol { case circle, triangle, square, star, line }
    let symbol: Symbol
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            switch symbol {
            case .circle:   Image(systemName: "circle.fill").font(.system(size: 8)).foregroundStyle(color)
            case .triangle: Image(systemName: "triangle.fill").font(.system(size: 8)).foregroundStyle(color)
            case .square:   Image(systemName: "square.fill").font(.system(size: 8)).foregroundStyle(color)
            case .star:     Image(systemName: "asterisk").font(.system(size: 9, weight: .bold)).foregroundStyle(color)
            case .line:     Capsule().fill(color).frame(width: 14, height: 2)
            }
            Text(label).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 今回 vs 直近5回平均（Player Data タブから移動）

struct RecentComparisonCard: View {
    let sessions: [TrainingSession]

    private var comparison: PlayerDataEngine.SessionComparison? {
        PlayerDataEngine.compareToRecentAverage(sessions: sessions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今回 vs 直近5回平均")
                .font(.subheadline.bold())

            if let comparison {
                HStack {
                    VStack(spacing: 2) {
                        Text(formatDistance(comparison.currentDistance))
                            .font(.title3.bold())
                        Text(formatDuration(comparison.currentDuration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("今回")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%+.0f%%", comparison.percentDiff))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(comparison.percentDiff >= 0 ? Color.green : Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Spacer()
                    VStack(spacing: 2) {
                        Text(formatDistance(comparison.recentAverageDistance))
                            .font(.title3.bold())
                        Text(formatDuration(comparison.recentAverageDuration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("直近5回平均")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("セッションが6件以上貯まると表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1fkm", meters / 1000) : String(format: "%.0fm", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分"
    }
}
