//
//  HeartRateAnalysis.swift
//  FootballGPS
//
//  心拍の推移とゾーンの計算（技術実装仕様書 §25.3）
//

import SwiftUI

/// 推定最大心拍に対する割合で分けた心拍ゾーン
enum HeartRateZone: Int, CaseIterable, Identifiable {
    case rest, z1, z2, z3, z4, z5

    var id: Int { rawValue }

    /// ゾーンの下限（推定最大心拍に対する割合）
    var lowerRatio: Double {
        switch self {
        case .rest: return 0
        case .z1:   return 0.5
        case .z2:   return 0.6
        case .z3:   return 0.7
        case .z4:   return 0.8
        case .z5:   return 0.9
        }
    }

    /// ゾーンの上限（推定最大心拍に対する割合）。Z5 は上限なし
    var upperRatio: Double? {
        HeartRateZone(rawValue: rawValue + 1)?.lowerRatio
    }

    var label: String {
        switch self {
        case .rest: return "安静"
        default:    return "Z\(rawValue)"
        }
    }

    var rangeText: String {
        switch self {
        case .rest: return "50%未満"
        case .z5:   return "90%以上"
        default:    return "\(Int(lowerRatio * 100))〜\(Int((upperRatio ?? 1) * 100))%"
        }
    }

    var color: Color {
        switch self {
        case .rest: return .gray
        case .z1:   return .blue
        case .z2:   return .green
        case .z3:   return .yellow
        case .z4:   return .orange
        case .z5:   return .red
        }
    }

    static func zone(for bpm: Double, maxHR: Double) -> HeartRateZone {
        let ratio = bpm / maxHR
        return allCases.last(where: { ratio >= $0.lowerRatio }) ?? .rest
    }
}

/// 1セッション（またはドリル区間）の心拍の集計
struct HeartRateSummary {
    let averageBPM: Double
    let maxBPM: Double
    /// 推定最大心拍。生年月日が未設定なら nil（ゾーンは出さない）
    let estimatedMaxHR: Double?
    /// ゾーンごとの時間（秒）。estimatedMaxHR が nil なら空
    let zoneDurations: [HeartRateZone: TimeInterval]
    /// 時間で数えた区間の合計（秒）
    let countedDuration: TimeInterval

    /// Z4＋Z5 の時間の割合（0…100%）。ゾーンを出せないときや数えた時間がないときは nil
    var highIntensityRatio: Double? {
        guard estimatedMaxHR != nil, countedDuration > 0 else { return nil }
        let high = (zoneDurations[.z4] ?? 0) + (zoneDurations[.z5] ?? 0)
        return high / countedDuration * 100
    }
}

enum HeartRateAnalysis {
    /// これより間が空いた区間は、一時停止や記録の抜けとみなして数えない（秒）
    static let maxSampleGap: TimeInterval = 30

    /// 計算に使う心拍の列（時刻順）。GPSとは別に記録した心拍があればそれを、
    /// なければ GPS の点に付いた心拍を使う（§25.3）
    static func series(heartRateSamples: [HeartRateSample]?, points: [GPSPoint]) -> [HeartRateSample] {
        if let heartRateSamples, !heartRateSamples.isEmpty {
            return heartRateSamples.sorted { $0.timestamp < $1.timestamp }
        }
        return points.compactMap { point in
            point.heartRate.map { HeartRateSample(timestamp: point.timestamp, bpm: $0) }
        }
    }

    static func series(for gpsData: GPSData) -> [HeartRateSample] {
        series(heartRateSamples: gpsData.heartRateSamples, points: gpsData.points)
    }

    /// 切り出した GPS 点の時間の範囲に入る心拍だけを残す（ドリルの分割・手動の切り出し用）
    static func sliced(_ samples: [HeartRateSample]?, toRangeOf points: [GPSPoint]) -> [HeartRateSample]? {
        guard let samples, let first = points.first, let last = points.last else { return nil }
        return samples.filter { $0.timestamp >= first.timestamp && $0.timestamp <= last.timestamp }
    }

    /// 各記録の値が次の記録まで続いたとみなした時間。間が maxSampleGap を超える区間は 0（数えない）。
    /// 最後の記録は 0
    static func weightedDurations(_ series: [HeartRateSample]) -> [TimeInterval] {
        series.indices.map { i in
            guard i + 1 < series.count else { return 0 }
            let gap = series[i + 1].timestamp.timeIntervalSince(series[i].timestamp)
            return gap > maxSampleGap ? 0 : max(0, gap)
        }
    }

    /// 心拍の列を集計する。記録がなければ nil
    static func summarize(_ series: [HeartRateSample], age: Int?) -> HeartRateSummary? {
        guard !series.isEmpty else { return nil }
        let durations = weightedDurations(series)
        let counted = durations.reduce(0, +)

        let average: Double
        if counted > 0 {
            average = zip(series, durations).map { $0.bpm * $1 }.reduce(0, +) / counted
        } else {
            average = series.map(\.bpm).reduce(0, +) / Double(series.count)
        }

        let maxHR = age.map { SessionDataManager.maxHeartRate(age: $0) }
        var zoneDurations: [HeartRateZone: TimeInterval] = [:]
        if let maxHR {
            for (sample, duration) in zip(series, durations) where duration > 0 {
                zoneDurations[HeartRateZone.zone(for: sample.bpm, maxHR: maxHR), default: 0] += duration
            }
        }

        return HeartRateSummary(
            averageBPM: average,
            maxBPM: series.map(\.bpm).max() ?? average,
            estimatedMaxHR: maxHR,
            zoneDurations: zoneDurations,
            countedDuration: counted
        )
    }

    /// 時間の範囲内の心拍の平均。範囲内に記録がなければ、開始前 maxSampleGap 以内の直近の記録を使う
    static func averageBPM(in series: [HeartRateSample], from start: Date, to end: Date) -> Double? {
        let inRange = series.filter { $0.timestamp >= start && $0.timestamp <= end }
        if !inRange.isEmpty {
            return inRange.map(\.bpm).reduce(0, +) / Double(inRange.count)
        }
        guard let before = series.last(where: { $0.timestamp < start }),
              start.timeIntervalSince(before.timestamp) <= maxSampleGap else { return nil }
        return before.bpm
    }
}
