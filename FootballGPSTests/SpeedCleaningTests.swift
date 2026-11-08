//
//  SpeedCleaningTests.swift
//  FootballGPSTests
//
//  iPhone側の速度の外れ値除去（docs/技術実装仕様書.md §1.8）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct SpeedCleaningTests {

    /// 1秒間隔で、指定した速度（km/h）の点列を作る
    private func points(_ kmh: [Double]) -> [GPSPoint] {
        kmh.enumerated().map { i, v in
            GPSPoint(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                latitude: 35.68 + Double(i) * 0.00001,
                longitude: 139.76,
                speed: v / 3.6,
                altitude: 0,
                horizontalAccuracy: 5
            )
        }
    }

    private func kmh(_ points: [GPSPoint]) -> [Double] {
        points.map { ($0.speed * 3.6 * 10).rounded() / 10 }
    }

    @Test func 前後が10kmhで1点だけ30kmhなら消える() {
        let cleaned = SessionDataManager.removingSpeedSpikes(points([10, 10, 30, 10, 10]))
        #expect(kmh(cleaned) == [10, 10, 10, 10, 10])
    }

    @Test func 数秒かけて上がる本物のスプリントはそのまま() {
        let sprint: [Double] = [10, 15, 20, 25, 30, 30, 28, 22, 15, 10]
        let cleaned = SessionDataManager.removingSpeedSpikes(points(sprint))
        #expect(kmh(cleaned) == sprint)
    }

    @Test func 上がる側か下がる側の片方だけが急でも置き換えない() {
        // 急に上がるが、その後は高い速度が続く（急停止ではない）
        let cleaned = SessionDataManager.removingSpeedSpikes(points([5, 30, 30, 30]))
        #expect(kmh(cleaned)[1] == 30)
    }

    @Test func 誤読が続いて38kmhを超える点は上限以内の点で補う() {
        let cleaned = SessionDataManager.removingSpeedSpikes(points([20, 21, 45, 45, 22, 20]))
        #expect(kmh(cleaned).allSatisfy { $0 <= 38 })
        #expect(abs(kmh(cleaned)[2] - 21.5) < 0.1)
    }

    @Test func 先頭や末尾の1点だけの飛びも置き換える() {
        let cleaned = SessionDataManager.removingSpeedSpikes(points([30, 10, 10, 10, 30]))
        #expect(kmh(cleaned) == [10, 10, 10, 10, 10])
    }

    @Test func 点の数と位置は変えない() {
        let original = points([10, 10, 30, 10, 10])
        let cleaned = SessionDataManager.removingSpeedSpikes(original)
        #expect(cleaned.count == original.count)
        #expect(zip(cleaned, original).allSatisfy { $0.latitude == $1.latitude && $0.timestamp == $1.timestamp })
    }

    @Test func 最高速度は2回続けて記録された速度から計算する() {
        // 33 は1点だけなので消える。20 も1点だけなので、続けて記録された 18 が最高速度になる
        let maxKmh = SessionDataManager.cleanedMaxSpeed(points([10, 12, 33, 12, 10, 18, 20, 18])) * 3.6
        #expect(abs(maxKmh - 18) < 0.01)
    }

    @Test func 上下に揺れながら上がる誤読も消える() {
        // 2026-07-20 09:38 の実データの並び（ほぼ1秒間隔）。旧ルール（加速の限界 5m/s²）では見逃していた
        let maxKmh = SessionDataManager.cleanedMaxSpeed(points([19, 19, 7, 25, 33, 6, 5, 5])) * 3.6
        #expect(maxKmh <= 25)
    }

    @Test func 一点だけの飛びはスプリントに数えない() {
        let spike = points([8, 8, 8, 30, 8, 8, 8])
        #expect(SessionDataManager.computeSprintSegments(spike).isEmpty)
    }

    // MARK: - 2点まで続く誤読の山（§1.8 の 3）

    /// 1秒間隔の点列。位置は positionKmh の速さで北へ進める（nil なら速度と同じ速さで進む）
    private func track(_ kmh: [Double], accuracy: Double, positionKmh: Double? = nil) -> [GPSPoint] {
        var latitude = 35.68
        return kmh.enumerated().map { i, v in
            if i > 0 { latitude += (positionKmh ?? v) / 3.6 / 111_320 }
            return GPSPoint(
                timestamp: Date(timeIntervalSince1970: Double(i)),
                latitude: latitude,
                longitude: 139.76,
                speed: v / 3.6,
                altitude: 0,
                horizontalAccuracy: accuracy
            )
        }
    }

    @Test func GPS精度が悪い2点だけの山は消える() {
        let maxKmh = SessionDataManager.cleanedMaxSpeed(track([12, 12, 12, 25, 25, 12, 12, 12], accuracy: 14.2)) * 3.6
        #expect(abs(maxKmh - 12) < 0.01)
    }

    @Test func 位置の動きと合わない2点だけの山は消える() {
        // 精度は良いが、位置は時速12kmでしか動いていない
        let maxKmh = SessionDataManager.cleanedMaxSpeed(
            track([12, 12, 12, 25, 25, 12, 12, 12], accuracy: 3, positionKmh: 12)
        ) * 3.6
        #expect(abs(maxKmh - 12) < 0.01)
    }

    @Test func 精度が良く位置とも合う2点の山は残る() {
        let maxKmh = SessionDataManager.cleanedMaxSpeed(track([12, 12, 12, 25, 25, 12, 12, 12], accuracy: 3)) * 3.6
        #expect(abs(maxKmh - 25) < 0.01)
    }

    @Test func 前後との差が小さい山は精度が悪くても残る() {
        // 2026-07-20 09:04 の実データの形（19.6 → 25.1 → 20.8）
        let maxKmh = SessionDataManager.cleanedMaxSpeed(
            track([18, 18, 19.6, 25.1, 25.1, 20.8, 16, 10], accuracy: 14.2)
        ) * 3.6
        #expect(abs(maxKmh - 25.1) < 0.01)
    }

    @Test func 実データの誤読の山は消える() {
        // 2026-07-03 11:23 の実データの形（精度14.2m、12.5 → 24.6 → 4.7）
        let maxKmh = SessionDataManager.cleanedMaxSpeed(
            track([4.7, 5.2, 12.5, 24.6, 24.6, 4.7, 3.9, 4.2], accuracy: 14.2)
        ) * 3.6
        #expect(maxKmh < 13)
    }

    // MARK: - スプリントの基準（§13.4）

    private func thresholdKmh(_ age: Int?, _ gender: Gender?) -> Double {
        (SessionDataManager.sprintThreshold(age: age, gender: gender) * 3.6 * 10).rounded() / 10
    }

    @Test func 男子のスプリント基準() {
        let expected: [(Int, Double)] = [
            (11, 16), (12, 18), (13, 19.5), (14, 20), (15, 20), (16, 25), (39, 25),
            (40, 18.5), (49, 18.5), (50, 17.5), (59, 17.5), (60, 16.5), (69, 16.5), (70, 15), (85, 15),
        ]
        for (age, kmh) in expected {
            #expect(thresholdKmh(age, .male) == kmh, "\(age)歳")
        }
    }

    @Test func 女子のスプリント基準() {
        let expected: [(Int, Double)] = [
            (11, 16), (12, 18), (13, 20.5), (15, 20.5), (16, 23), (39, 23),
            (40, 16), (50, 15.5), (60, 14.5), (70, 13),
        ]
        for (age, kmh) in expected {
            #expect(thresholdKmh(age, .female) == kmh, "\(age)歳")
        }
    }

    @Test func 年齢や性別が未設定ならプロの男子の基準() {
        #expect(thresholdKmh(nil, nil) == 25)
        #expect(thresholdKmh(nil, .female) == 23)
        #expect(thresholdKmh(45, nil) == 18.5)
    }
}
