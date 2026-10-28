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
        // フィールド内と確認できた最後の点(120)が退場後休憩の開始点になる（速度に関わらず無条件除外のため）
        #expect(breaks[0].startOffset == 120)
        #expect(breaks[0].endOffset == 215)
    }

    @Test func フィールド入場前の通常速度の徒歩は速度に関わらず除外される() {
        // 開始直後、通常の速さ(低速度しきい値超)でフィールドへ歩く区間(90秒) → フィールド入場後ドリル
        var points = run(from: 0, duration: 90, inside: false, speed: 1.5) // 1.5m/s > lowSpeedThreshold(1.0)
        points += run(from: 95, duration: 120, inside: true, speed: 3.0)

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 0)
        #expect(breaks[0].endOffset == 95) // フィールドに最初に入った時刻

        let totalDuration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: totalDuration, breaks: breaks)
        // 入場前の徒歩が偽のドリルとして残らないこと（ドリルは1本のみ）
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 95)
    }

    @Test func フィールド退場後の通常速度の徒歩も速度に関わらず除外される() {
        var points = run(from: 0, duration: 120, inside: true, speed: 3.0)
        points += run(from: 125, duration: 90, inside: false, speed: 1.5) // 通常速度で退場後の徒歩

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 120)

        let totalDuration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: totalDuration, breaks: breaks)
        #expect(ranges.count == 1)
        #expect(ranges[0].end == 120)
    }

    @Test func 入場前に速歩と静止が混在しても1つの除外区間としてまとまる() {
        // ユーザー指摘の実運用シナリオ: 速歩(通常速度)で歩いた後、少し座って待つ、その後フィールドへ
        var points = run(from: 0, duration: 90, inside: false, speed: 1.5)   // 速歩(90秒)
        points += run(from: 95, duration: 70, inside: false, speed: 0.1)     // 静止(70秒)
        points += run(from: 170, duration: 120, inside: true, speed: 3.0)    // フィールド内でドリル

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 0)
        #expect(breaks[0].endOffset == 170) // フィールドに最初に入った時刻

        let totalDuration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: totalDuration, breaks: breaks)
        #expect(ranges.count == 1) // 速歩+静止の合計160秒が、偽のドリルにならず1つの除外区間にまとまる
        #expect(ranges[0].start == 170)
    }

    @Test func 中断が許容範囲内なら休憩は継続しているとみなされる() {
        // ユーザーが実機で報告した不具合の再現: 退場〜再入場の間、完全に静止し続けたわけではなく
        // 一瞬動いた(GPSノイズ含む)ことで休憩判定が途切れてしまうケース
        var points = run(from: 0, duration: 60, inside: true, speed: 3.0)   // ドリル1
        points += run(from: 65, duration: 30, inside: false, speed: 0.2)    // 静止(30秒): 65-95
        points += [point(t: 100, inside: false, speed: 1.5), point(t: 105, inside: false, speed: 1.5)] // 短い中断(10秒、許容範囲内)
        points += run(from: 110, duration: 30, inside: false, speed: 0.2)   // 静止再開(30秒): 110-140
        points += run(from: 145, duration: 60, inside: true, speed: 3.0)    // ドリル2

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        #expect(breaks.count == 1)
        #expect(breaks[0].startOffset == 65)
        #expect(breaks[0].endOffset == 145) // フィールドに戻った時刻で確定

        let totalDuration = points.last!.timestamp.timeIntervalSince(points.first!.timestamp)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: totalDuration, breaks: breaks)
        #expect(ranges.count == 2) // ドリル1・ドリル2の2本に正しく分割される
    }

    @Test func 中断が許容範囲を超えると休憩は分断され60秒未満なら確定しない() {
        var points = run(from: 0, duration: 60, inside: true, speed: 3.0)   // ドリル1
        points += run(from: 65, duration: 30, inside: false, speed: 0.2)    // 静止(30秒、単体では60秒未満)
        points += run(from: 100, duration: 20, inside: false, speed: 1.5)   // 中断(20秒 > 許容15秒)
        points += run(from: 125, duration: 30, inside: false, speed: 0.2)   // 静止再開(30秒、これも単体では60秒未満)
        points += run(from: 160, duration: 60, inside: true, speed: 3.0)    // ドリル2

        let breaks = DrillSplitDetector.detectBreaks(points: points, field: field)
        // 中断が許容範囲を超えるため休憩が前後半に分断され、どちらも60秒未満のため確定しない
        #expect(breaks.isEmpty)
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

    // MARK: - 手動分割

    @Test func 手動_区切りなしなら全体が1本() {
        let ranges = DrillSplitDetector.manualRanges(cutOffsets: [], isDrill: [true], totalDuration: 600)
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 0 && ranges[0].end == 600)
    }

    @Test func 手動_先頭を休憩にすると開始位置だけ変わる() {
        let ranges = DrillSplitDetector.manualRanges(cutOffsets: [120], isDrill: [false, true], totalDuration: 600)
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 120 && ranges[0].end == 600)
    }

    @Test func 手動_ドリル同士が隣り合っても別々の区間になる() {
        let ranges = DrillSplitDetector.manualRanges(
            cutOffsets: [300, 420, 900],
            isDrill: [true, false, true, true],
            totalDuration: 1200
        )
        #expect(ranges.count == 3)
        #expect(ranges[0].start == 0 && ranges[0].end == 300)
        #expect(ranges[1].start == 420 && ranges[1].end == 900)
        #expect(ranges[2].start == 900 && ranges[2].end == 1200)
    }

    @Test func 手動_先頭と末尾の休憩はドリルに含まれない() {
        let ranges = DrillSplitDetector.manualRanges(
            cutOffsets: [60, 500, 560],
            isDrill: [false, true, false, false],
            totalDuration: 600
        )
        #expect(ranges.count == 1)
        #expect(ranges[0].start == 60 && ranges[0].end == 500)
    }

    @Test func 手動_自動検出の区間から初期状態を作り元の区間に戻せる() {
        // 入場前の移動(0-30)、ドリル(30-300)、休憩(300-420)、ドリル(420-900)、退場後の移動(900-1000)
        let autoRanges: [(start: TimeInterval, end: TimeInterval)] = [(30, 300), (420, 900)]
        let state = DrillSplitDetector.manualState(fromDrillRanges: autoRanges, totalDuration: 1000)
        #expect(state.cutOffsets == [30, 300, 420, 900])
        #expect(state.isDrill == [false, true, false, true, false])

        let ranges = DrillSplitDetector.manualRanges(
            cutOffsets: state.cutOffsets, isDrill: state.isDrill, totalDuration: 1000
        )
        #expect(ranges.count == 2)
        #expect(ranges[0].start == 30 && ranges[0].end == 300)
        #expect(ranges[1].start == 420 && ranges[1].end == 900)
    }

    @Test func 手動_自動検出で捨てた短い断片は前後の休憩とまとまる() {
        // segmentRanges が捨てた 300-330 の断片は、ドリル区間の境目ではないため区切りにならない
        let autoRanges: [(start: TimeInterval, end: TimeInterval)] = [(0, 300), (500, 800)]
        let state = DrillSplitDetector.manualState(fromDrillRanges: autoRanges, totalDuration: 800)
        #expect(state.cutOffsets == [300, 500])
        #expect(state.isDrill == [true, false, true])
    }
}
