//
//  CourtOrientationTests.swift
//  FootballGPSTests
//
//  後半の入れ替え（機能仕様書 §9.4）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct CourtOrientationTests {

    // フィールド: 南西 (35.6803, 139.7671) 〜 北東 (35.6813, 139.7681)。下（南）が自陣ゴール
    private let field = Field(
        teamId: "team",
        name: "テストフィールド",
        createdBy: "user",
        corners: Field.FieldCorners(
            topLeft: Field.Coordinate(latitude: 35.6813, longitude: 139.7671),
            topRight: Field.Coordinate(latitude: 35.6813, longitude: 139.7681),
            bottomRight: Field.Coordinate(latitude: 35.6803, longitude: 139.7681),
            bottomLeft: Field.Coordinate(latitude: 35.6803, longitude: 139.7671)
        )
    )

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    /// フィールド内の割合座標（fx: 左→右, fy: 自陣→敵陣）の点
    private func point(at seconds: TimeInterval, fx: Double, fy: Double) -> GPSPoint {
        GPSPoint(
            timestamp: date(seconds),
            latitude: 35.6803 + fy * 0.001,
            longitude: 139.7671 + fx * 0.001,
            speed: 2,
            altitude: 0,
            horizontalAccuracy: 5
        )
    }

    /// 前半は実際の座標で fy=0.8 付近、後半は陣地が入れ替わって fy=0.2 付近でプレーした記録
    private func matchPoints() -> [GPSPoint] {
        let firstHalf = (0..<100).map { point(at: Double($0), fx: 0.5, fy: 0.8) }
        let secondHalf = (100..<200).map { point(at: Double($0), fx: 0.5, fy: 0.2) }
        return firstHalf + secondHalf
    }

    @Test func 入れ替えの時刻より前は元の向きで以降は逆になる() {
        let orientation = CourtOrientation(isFlipped: false, switchDate: date(100))
        #expect(orientation.isFlipped(at: date(99)) == false)
        #expect(orientation.isFlipped(at: date(100)) == true)
        #expect(CourtOrientation(isFlipped: true, switchDate: date(100)).isFlipped(at: date(100)) == false)
    }

    @Test func 入れ替えがなければ全体が同じ向きになる() {
        let orientation = CourtOrientation(isFlipped: true)
        #expect(orientation.isFlipped(at: date(0)) == true)
        #expect(orientation.isFlipped(at: date(1000)) == true)
    }

    @Test func 入れ替えを設定すると後半の点が前半と同じ側に重なる() throws {
        let points = matchPoints()
        let plain = HeatmapGrid.normalizedPoints(points, field: field, orientation: CourtOrientation(isFlipped: false))
        #expect(abs(try #require(plain.last).y - 0.2) < 0.02)

        let switched = HeatmapGrid.normalizedPoints(
            points, field: field, orientation: CourtOrientation(isFlipped: false, switchDate: date(100))
        )
        #expect(abs(try #require(switched.first).y - 0.8) < 0.02)
        #expect(abs(try #require(switched.last).y - 0.8) < 0.02)
    }

    @Test func サード割合と立ち位置にも入れ替えが反映される() throws {
        let gpsData = GPSData(sessionId: "s", points: matchPoints())

        let plain = SessionDataManager.computeThirdRatios(
            gpsData: gpsData, field: field, orientation: CourtOrientation(isFlipped: false)
        )
        #expect(plain.attacking == 50)
        #expect(plain.defensive == 50)

        let switchedOrientation = CourtOrientation(isFlipped: false, switchDate: date(100))
        let switched = SessionDataManager.computeThirdRatios(gpsData: gpsData, field: field, orientation: switchedOrientation)
        #expect(switched.attacking == 100)

        let heights = try #require(
            SessionDataManager.computePositionHeights(gpsData: gpsData, field: field, orientation: switchedOrientation)
        )
        #expect(abs(heights.avg - 80) < 2)
    }

    @Test func 切り出した点列でも同じ向きになる() throws {
        let points = matchPoints()
        let orientation = CourtOrientation(isFlipped: false, switchDate: date(100))
        let whole = HeatmapGrid.normalizedPoints(points, field: field, orientation: orientation)
        let sliced = HeatmapGrid.normalizedPoints(Array(points[150...160]), field: field, orientation: orientation)
        #expect(sliced.first == whole[150])
        #expect(sliced.last == whole[160])
    }

    @Test func 入れ替えの前後に点列を分ける() {
        let points = matchPoints()
        let parts = CourtOrientation(isFlipped: false, switchDate: date(100)).splitAtSwitch(points)
        #expect(parts.map(\.count) == [100, 100])
        #expect(CourtOrientation(isFlipped: false).splitAtSwitch(points).map(\.count) == [200])
        #expect(CourtOrientation(isFlipped: false, switchDate: date(500)).splitAtSwitch(points).map(\.count) == [200])
    }

    @Test func 切り出す範囲に入れ替えがなければその範囲の向きに固定する() {
        let orientation = CourtOrientation(isFlipped: false, switchDate: date(100))
        #expect(orientation.clipped(from: date(0), to: date(50)) == CourtOrientation(isFlipped: false))
        #expect(orientation.clipped(from: date(100), to: date(150)) == CourtOrientation(isFlipped: true))
        #expect(orientation.clipped(from: date(50), to: date(150)) == orientation)
    }

    @Test func ハーフタイムの候補は記録の中ほどの一番長い休憩の終わりになる() {
        let breaks = [
            DrillBreakInterval(startOffset: 0, endOffset: 300),         // 入場前
            DrillBreakInterval(startOffset: 1000, endOffset: 1100),     // 短い中断
            DrillBreakInterval(startOffset: 1800, endOffset: 2400),     // ハーフタイム
            DrillBreakInterval(startOffset: 3500, endOffset: 4000),     // 退場後
        ]
        #expect(DrillSplitDetector.suggestedCourtSwitchOffset(breaks: breaks, totalDuration: 4000) == 2400)
    }

    @Test func ハーフタイムの候補がなければ記録の真ん中になる() {
        let breaks = [DrillBreakInterval(startOffset: 0, endOffset: 300)]
        #expect(DrillSplitDetector.suggestedCourtSwitchOffset(breaks: breaks, totalDuration: 4000) == 2000)
    }
}
