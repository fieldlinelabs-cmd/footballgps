//
//  ViewsHeartRateSection.swift
//  FootballGPS
//
//  セッション詳細の「心拍」セクション（技術実装仕様書 §25.5）
//

import SwiftUI
import Charts

struct HeartRateSection: View {
    let series: [HeartRateSample]
    let summary: HeartRateSummary
    /// 横軸の経過時間の起点（セッションの開始時刻）
    let startDate: Date

    /// グラフ用の点。間が HeartRateAnalysis.maxSampleGap を超えるところで線を切るため、区切りの番号を持つ
    private struct ChartPoint: Identifiable {
        let id: Int
        let minutes: Double
        let bpm: Double
        let segment: Int
    }

    private var chartPoints: [ChartPoint] {
        var segment = 0
        return series.enumerated().map { i, sample in
            if i > 0, sample.timestamp.timeIntervalSince(series[i - 1].timestamp) > HeartRateAnalysis.maxSampleGap {
                segment += 1
            }
            return ChartPoint(
                id: i,
                minutes: sample.timestamp.timeIntervalSince(startDate) / 60,
                bpm: sample.bpm,
                segment: segment
            )
        }
    }

    /// 縦軸の範囲。ゾーンの帯が見えるよう、推定最大心拍があればその50%〜100%を含める
    private var yDomain: ClosedRange<Double> {
        let bpms = series.map(\.bpm)
        var lower = (bpms.min() ?? 60) - 10
        var upper = (bpms.max() ?? 180) + 10
        if let maxHR = summary.estimatedMaxHR {
            lower = min(lower, maxHR * HeartRateZone.z1.lowerRatio)
            upper = max(upper, maxHR)
        }
        return max(0, lower)...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                valueBlock(title: "平均心拍", bpm: summary.averageBPM, alignment: .leading)
                Spacer()
                valueBlock(title: "最大心拍", bpm: summary.maxBPM, alignment: .trailing)
            }

            chart

            if summary.estimatedMaxHR != nil {
                zoneBreakdown
            } else {
                Text("プロフィールに生年月日を入れると、心拍ゾーンが表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func valueBlock(title: String, bpm: Double, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(format: "%.0f bpm", bpm))
                .font(.title2.bold())
                .foregroundStyle(.red)
        }
    }

    private var chart: some View {
        let domain = yDomain
        return Chart {
            if let maxHR = summary.estimatedMaxHR {
                ForEach(HeartRateZone.allCases.filter { $0 != .rest }) { zone in
                    RectangleMark(
                        yStart: .value("下限", max(domain.lowerBound, maxHR * zone.lowerRatio)),
                        yEnd: .value("上限", min(domain.upperBound, maxHR * (zone.upperRatio ?? 2)))
                    )
                    .foregroundStyle(zone.color.opacity(0.12))
                }
            }
            ForEach(chartPoints) { point in
                LineMark(
                    x: .value("経過（分）", point.minutes),
                    y: .value("心拍", point.bpm),
                    series: .value("区間", point.segment)
                )
                .foregroundStyle(.red)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartYScale(domain: domain)
        .chartXAxisLabel("経過（分）")
        .chartYAxisLabel("bpm")
        .frame(height: 180)
    }

    private var zoneBreakdown: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ゾーンごとの時間")
                .font(.subheadline.bold())
            ForEach(HeartRateZone.allCases.reversed()) { zone in
                let duration = summary.zoneDurations[zone] ?? 0
                let ratio = summary.countedDuration > 0 ? duration / summary.countedDuration : 0
                HStack(spacing: 8) {
                    Text(zone.label)
                        .font(.caption.bold())
                        .frame(width: 32, alignment: .leading)
                    Text(zone.rangeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(.systemGray5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(zone.color)
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 10)
                    Text(String(format: "%.0f分 %.0f%%", duration / 60, ratio * 100))
                        .font(.caption2.monospacedDigit())
                        .frame(width: 72, alignment: .trailing)
                }
            }
            Text("ゾーンは年齢から推定した最大心拍（\(Int(summary.estimatedMaxHR ?? 0)) bpm）に対する割合です")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
