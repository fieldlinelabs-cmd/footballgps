//
//  DrillSplitDetectorTests.swift
//  FootballGPSTests
//

import Testing
import CoreLocation
@testable import FootballGPS

struct DrillSplitDetectorTests {

    // フィールド境界: 35.6803〜35.6813 / 139.7671〜139.7681（約100m四方）
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

    private let insideCoordinate = (lat: 35.6808, lon: 139.7676)
    private let outsideCoordinate = (lat: 35.6750, lon: 139.7671) // 明確にフィールド外

    private func point(t: TimeInterval, inside: Bool, speed: Double) -> GPSPoint {
        let coord = inside ? insideCoordinate : outsideCoordinate
        return GPSPoint(
            timestamp: Date(timeIntervalSince1970: t),
            latitude: coord.lat,
            longitude: coord.lon,
            speed: speed,
            altitude: 0,
            horizontalAccuracy: 5
        )
    }

    /// 一定区間、5秒間隔で点を生成する
    private func run(from startT: TimeInterval, duration: TimeInterval, inside: Bool, speed: Double) -> [GPSPoint] {
        stride(from: startT, through: startT + duration, by: 5).map { point(t: $0, inside: inside, speed: speed) }
    }

    @Test func 休憩なしなら分割なし() {
        let points = run(from: 0, duration: 300, inside: true, speed: 3.0)
        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.isEmpty)
    }

    @Test func 明確な一回の休憩を検出する() {
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 90, inside: false, speed: 0.2)
        points += run(from: 220, duration: 120, inside: true, speed: 3.0)

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 125)
        #expect(breaks[0].endOffset == 220)

        let ranges = DrillSplitDetector.segmentRanges(totalDuration: 340, breaks: breaks)
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 0 && ranges[0].end == 125)
        #expect(ranges[1].start == 220 && ranges[1].end == 340)
    }

    @Test func 短い滞在は休憩として確定しない() {
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 30, inside: false, speed: 0.2) // 30秒 < 60秒
        points += run(from: 160, duration: 120, inside: true, speed: 3.0)

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.isEmpty)
    }

    @Test func 練習終了時点でフィールド外にいたまま終了した休憩も検出する() {
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 90, inside: false, speed: 0.2) // 終了までフィールド外のまま

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 125)
        #expect(breaks[0].endOffset == 215)
    }

    @Test func 短すぎるドリル区間は分割対象から除外される() {
        // ドリル1(120s) → 休憩(70s) → ごく短いドリル(30s、閾値未満) → 休憩(70s) → ドリル2(120s)
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 70, inside: false, speed: 0.2)
        points += run(from: 200, duration: 30, inside: true, speed: 3.0) // 30秒 < minSegmentDuration(60秒)
        points += run(from: 235, duration: 70, inside: false, speed: 0.2)
        points += run(from: 310, duration: 120, inside: true, speed: 3.0)

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 2) // 休憩自体は2回とも60秒以上なので両方検出される

        let totalDuration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: totalDuration, breaks: breaks)
        // 真ん中の短いドリル(30秒)はminSegmentDuration未満のため捨てられ、2本のみ残る
        #expect(ranges.count == 2)
    }

    @Test func フィールド外でも高速移動中は休憩と判定しない() {
        // ボール拾い等でフィールド外に出るが速度が高い場合は休憩候補にしない
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 90, inside: false, speed: 3.0) // 低速でない
        points += run(from: 220, duration: 120, inside: true, speed: 3.0)

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.isEmpty)
    }
}
