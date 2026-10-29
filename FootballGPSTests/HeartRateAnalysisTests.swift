//
//  HeartRateAnalysisTests.swift
//  FootballGPSTests
//
//  心拍の推移とゾーンの計算（docs/技術実装仕様書.md §25.3）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct HeartRateAnalysisTests {

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    /// (開始からの秒, bpm) の組から心拍の列を作る
    private func samples(_ pairs: [(TimeInterval, Double)]) -> [HeartRateSample] {
        pairs.map { HeartRateSample(timestamp: start.addingTimeInterval($0.0), bpm: $0.1) }
    }

    private func point(at seconds: TimeInterval, heartRate: Double? = nil) -> GPSPoint {
        GPSPoint(
            timestamp: start.addingTimeInterval(seconds),
            latitude: 35.68, longitude: 139.76, speed: 2, altitude: 0, horizontalAccuracy: 5,
            heartRate: heartRate
        )
    }

    @Test func 平均は時間の重み付きで数える() throws {
        // 100bpm が 10秒、200bpm が 30秒続いた（最後の記録は数えない）
        let series = samples([(0, 100), (10, 200), (40, 150)])
        let summary = try #require(HeartRateAnalysis.summarize(series, age: nil))
        #expect(summary.countedDuration == 40)
        #expect(abs(summary.averageBPM - 175) < 0.001)
        #expect(summary.maxBPM == 200)
    }

    @Test func 間が30秒を超える区間は数えない() throws {
        let series = samples([(0, 100), (10, 100), (100, 200), (110, 200)])
        let summary = try #require(HeartRateAnalysis.summarize(series, age: nil))
        #expect(summary.countedDuration == 20)
        #expect(abs(summary.averageBPM - 150) < 0.001)
    }

    @Test func ゾーンと高強度の割合は時間で数える() throws {
        // 20歳: 推定最大心拍 200。Z4 は 160〜180、Z2 は 120〜140
        let series = samples([(0, 170), (10, 130), (40, 130)])
        let summary = try #require(HeartRateAnalysis.summarize(series, age: 20))
        #expect(summary.zoneDurations[.z4] == 10)
        #expect(summary.zoneDurations[.z2] == 30)
        #expect(abs((summary.highIntensityRatio ?? 0) - 25) < 0.001)
    }

    @Test func 生年月日がなければゾーンを出さない() throws {
        let summary = try #require(HeartRateAnalysis.summarize(samples([(0, 170), (10, 130)]), age: nil))
        #expect(summary.zoneDurations.isEmpty)
        #expect(summary.highIntensityRatio == nil)
    }

    @Test func ゾーンの境目() {
        #expect(HeartRateZone.zone(for: 99, maxHR: 200) == .rest)
        #expect(HeartRateZone.zone(for: 100, maxHR: 200) == .z1)
        #expect(HeartRateZone.zone(for: 160, maxHR: 200) == .z4)
        #expect(HeartRateZone.zone(for: 180, maxHR: 200) == .z5)
        #expect(HeartRateZone.zone(for: 230, maxHR: 200) == .z5)
    }

    @Test func 別に記録した心拍がなければGPSの点の心拍を使う() {
        let points = [point(at: 0, heartRate: 120), point(at: 5), point(at: 10, heartRate: 140)]
        let fromPoints = HeartRateAnalysis.series(heartRateSamples: nil, points: points)
        #expect(fromPoints.map(\.bpm) == [120, 140])

        let separate = samples([(0, 90), (5, 95)])
        #expect(HeartRateAnalysis.series(heartRateSamples: separate, points: points).map(\.bpm) == [90, 95])
    }

    @Test func 切り出しはGPSの点の時間の範囲に合わせる() {
        let all = samples([(0, 100), (10, 110), (20, 120), (30, 130)])
        let points = [point(at: 10), point(at: 20)]
        let sliced = HeartRateAnalysis.sliced(all, toRangeOf: points)
        #expect(sliced?.map(\.bpm) == [110, 120])
    }

    @Test func 区間内に記録がなければ直前30秒以内の記録を使う() {
        let series = samples([(0, 150), (50, 170)])
        let near = HeartRateAnalysis.averageBPM(in: series, from: start.addingTimeInterval(20), to: start.addingTimeInterval(25))
        #expect(near == 150)
        let far = HeartRateAnalysis.averageBPM(in: series, from: start.addingTimeInterval(40), to: start.addingTimeInterval(45))
        #expect(far == nil)
    }
}
