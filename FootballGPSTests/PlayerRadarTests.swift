//
//  PlayerRadarTests.swift
//  FootballGPSTests
//
//  4軸のレーダー（技術実装仕様書 §17.2）と高速ランニングの基準（§13.4.A）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct PlayerRadarTests {

    @Test func 値を45分あたりに換算する() {
        // 15分で2,000m・高速ランニング150m・スプリント5回 → 45分あたり 6,000m・450m・15回
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: 2_000, duration: 15 * 60, highSpeedDistance: 150, sprintCount: 5, maxSpeed: 25 / 3.6
        )
        #expect(abs(radar.distancePer45 - 6_000) < 0.001)
        #expect(abs(radar.highSpeedPer45 - 450) < 0.001)
        #expect(abs(radar.sprintsPer45 - 15) < 0.001)
        #expect(abs(radar.topSpeedKmh - 25) < 0.001)
    }

    @Test func 満点は世界トップの記録() {
        // 90分で13.7km・高速ランニング1,260m・スプリント66回・時速37.4km → すべて満点
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: 13_700, duration: 90 * 60, highSpeedDistance: 1_260, sprintCount: 66, maxSpeed: 37.4 / 3.6
        )
        #expect(radar.axisValues.allSatisfy { abs($0 - 1) < 0.001 })
        #expect(abs(radar.overallScore - 100) < 0.001)
    }

    @Test func 満点を超えても1で止める() {
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: 20_000, duration: 45 * 60, highSpeedDistance: 2_000, sprintCount: 100, maxSpeed: 40 / 3.6
        )
        #expect(radar.axisValues == [1, 1, 1, 1])
    }

    @Test func 高速ランニングが一番高いとハードワーカー() {
        // 45分で 走力 3,000m(0.44)・高速ランニング 600m(0.95)・スプリント 5回(0.15)・時速20km(0.53)
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: 3_000, duration: 45 * 60, highSpeedDistance: 600, sprintCount: 5, maxSpeed: 20 / 3.6
        )
        #expect(radar.playerType == .hardWorker)
    }

    @Test func 高速ランニングが未計算なら0として扱う() {
        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: 3_000, duration: 45 * 60, highSpeedDistance: nil, sprintCount: 5, maxSpeed: 20 / 3.6
        )
        #expect(radar.highSpeed == 0)
    }

    // MARK: - 高速ランニングの基準

    private func thresholdKmh(_ age: Int?, _ gender: Gender?) -> Double {
        (SessionDataManager.highSpeedThreshold(age: age, gender: gender) * 3.6 * 10).rounded() / 10
    }

    @Test func 男子の高速ランニングの基準() {
        let expected: [(Int, Double)] = [
            (11, 12.5), (12, 14.5), (13, 15.5), (15, 16), (16, 20), (39, 20),
            (40, 14.5), (50, 14), (60, 13), (70, 12),
        ]
        for (age, kmh) in expected {
            #expect(thresholdKmh(age, .male) == kmh, "\(age)歳")
        }
    }

    @Test func 女子の高速ランニングの基準() {
        let expected: [(Int, Double)] = [
            (11, 12.5), (12, 14.5), (13, 17.5), (16, 19), (39, 19),
            (40, 13.5), (50, 13), (60, 12), (70, 10.5),
        ]
        for (age, kmh) in expected {
            #expect(thresholdKmh(age, .female) == kmh, "\(age)歳")
        }
    }

    @Test func 高速ランニングの基準はスプリントより低い() {
        for gender in [Gender.male, .female] {
            for age in [10, 12, 13, 14, 20, 45, 55, 65, 75] {
                #expect(SessionDataManager.highSpeedThreshold(age: age, gender: gender)
                        < SessionDataManager.sprintThreshold(age: age, gender: gender))
            }
        }
    }
}
