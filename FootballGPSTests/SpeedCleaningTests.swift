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
}
