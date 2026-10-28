//
//  GrowthTrendTests.swift
//  FootballGPSTests
//
//  統計推移（docs/統計推移仕様書.md）のポジション推定・高さ・WB ルール・集計の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct PositionEstimationTests {

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

    /// フィールド内の割合座標（fx: 左→右, fy: 自陣→敵陣）の範囲に、格子状に点を置く
    private func gpsData(fx: ClosedRange<Double>, fy: ClosedRange<Double>, steps: Int = 12) -> GPSData {
        var points: [GPSPoint] = []
        var t = 0.0
        for i in 0..<steps {
            for j in 0..<steps {
                let x = fx.lowerBound + (fx.upperBound - fx.lowerBound) * Double(i) / Double(steps - 1)
                let y = fy.lowerBound + (fy.upperBound - fy.lowerBound) * Double(j) / Double(steps - 1)
                points.append(GPSPoint(
                    timestamp: Date(timeIntervalSince1970: t),
                    latitude: 35.6803 + y * 0.001,
                    longitude: 139.7671 + x * 0.001,
                    speed: 2,
                    altitude: 0,
                    horizontalAccuracy: 5
                ))
                t += 1
            }
        }
        return GPSData(sessionId: "s", points: points)
    }

    @Test func 自陣ゴール前だけにいるとGKと推定される() {
        let data = gpsData(fx: 0.4...0.6, fy: 0.0...0.06)
        #expect(SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: false) == .gk)
    }

    @Test func 敵陣ゴール前の中央にいるとFWと推定される() {
        let data = gpsData(fx: 0.4...0.6, fy: 0.75...0.92)
        #expect(SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: false) == .fw)
    }

    @Test func 中央を縦に広く動くとMFと推定される() {
        let data = gpsData(fx: 0.4...0.6, fy: 0.2...0.8)
        #expect(SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: false) == .mf)
    }

    @Test func コート入れ替えで向きが反映される() {
        let data = gpsData(fx: 0.4...0.6, fy: 0.75...0.92)
        // 入れ替えると敵陣ゴール前が自陣ゴール寄りになり、FW ではなくなる
        let flipped = SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: true)
        #expect(flipped != .fw)
        #expect(flipped != nil)
    }

    @Test func 推定結果がWBになることはない() {
        let samples = [
            gpsData(fx: 0.0...0.1, fy: 0.1...0.9),
            gpsData(fx: 0.9...1.0, fy: 0.3...0.95),
            gpsData(fx: 0.0...1.0, fy: 0.0...1.0),
        ]
        for data in samples {
            #expect(SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: false) != .wb)
        }
    }

    @Test func フィールド内の点が60点未満なら推定も高さもnil() {
        let data = gpsData(fx: 0.4...0.6, fy: 0.4...0.6, steps: 7) // 49点
        #expect(SessionDataManager.predictPosition(gpsData: data, field: field, isFlipped: false) == nil)
        #expect(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: false) == nil)
    }

    @Test func センターラインだけにいると高さは約50パーセント() throws {
        let data = gpsData(fx: 0.2...0.8, fy: 0.5...0.5)
        let heights = try #require(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: false))
        #expect(abs(heights.avg - 50) < 1)
        #expect(abs(heights.front - 50) < 1)
        #expect(abs(heights.back - 50) < 1)
    }

    @Test func 最低線は前線から戻ってきた位置の5パーセンタイル() throws {
        // 敵陣寄り（80%）に多くいて、一部だけ自陣寄り（20%）まで戻った FW
        let forward = gpsData(fx: 0.4...0.6, fy: 0.8...0.8).points
        let defending = gpsData(fx: 0.4...0.6, fy: 0.2...0.2, steps: 4).points
        let data = GPSData(sessionId: "s", points: forward + defending)
        let heights = try #require(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: false))
        #expect(abs(heights.front - 80) < 1)
        #expect(abs(heights.back - 20) < 1)
    }

    @Test func フィールド外の点は0から100パーセントにクランプされる() throws {
        let inside = gpsData(fx: 0.2...0.8, fy: 0.5...0.5).points
        let outside = gpsData(fx: 0.2...0.8, fy: 1.3...1.3).points
        let data = GPSData(sessionId: "s", points: inside + outside)
        let heights = try #require(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: false))
        #expect(abs(heights.avg - 75) < 1)
        #expect(abs(heights.front - 100) < 0.001)
        #expect(abs(heights.back - 50) < 1)
    }

    @Test func コート入れ替えで高さが反転する() throws {
        let data = gpsData(fx: 0.2...0.8, fy: 0.2...0.2)
        let normal = try #require(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: false))
        let flipped = try #require(SessionDataManager.computePositionHeights(gpsData: data, field: field, isFlipped: true))
        #expect(abs(normal.avg - 20) < 1)
        #expect(abs(flipped.avg - 80) < 1)
    }
}

@MainActor
struct WingBackRuleTests {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(_ id: String, day: Int, estimated: PlayingPosition?, manual: PlayingPosition? = nil) -> TrainingSession {
        TrainingSession(
            id: id,
            userId: "u",
            date: base.addingTimeInterval(Double(day) * 86400),
            duration: 3600,
            position: manual,
            positionSource: manual == nil ? (estimated == nil ? nil : .auto) : .manual,
            estimatedPosition: estimated
        )
    }

    private func positions(_ sessions: [TrainingSession]) -> [String: PlayingPosition?] {
        Dictionary(uniqueKeysWithValues: SessionDataManager.applyingWingBackRule(to: sessions).map { ($0.id, $0.position) })
    }

    @Test func 手動でWBにした後はSBとWGの推定がWBになりMFはそのまま() {
        let result = positions([
            session("manual", day: 0, estimated: .sb, manual: .wb),
            session("sb", day: 1, estimated: .sb),
            session("wg", day: 2, estimated: .wg),
            session("mf", day: 3, estimated: .mf),
        ])
        #expect(result["sb"] == .wb)
        #expect(result["wg"] == .wb)
        #expect(result["mf"] == .mf)
        #expect(result["manual"] == .wb)
    }

    @Test func 手動WBのあとに手動CBにするとそれ以降はルールが働かない() {
        let result = positions([
            session("wb", day: 0, estimated: .sb, manual: .wb),
            session("between", day: 1, estimated: .sb),
            session("cb", day: 2, estimated: .cb, manual: .cb),
            session("after", day: 3, estimated: .sb),
        ])
        #expect(result["between"] == .wb)
        #expect(result["after"] == .sb)
    }

    @Test func 手動で設定したセッションより前のセッションにはルールが働かない() {
        let result = positions([
            session("before", day: 0, estimated: .wg),
            session("wb", day: 1, estimated: .wg, manual: .wb),
        ])
        #expect(result["before"] == .wg)
    }

    @Test func 手動で設定したセッションのポジションは推定に関係なく変わらない() {
        let result = positions([
            session("wb", day: 0, estimated: .sb, manual: .wb),
            session("manualMF", day: 1, estimated: .sb, manual: .mf),
        ])
        #expect(result["manualMF"] == .mf)
    }

    @Test func 推定できないセッションは未設定のまま() {
        let result = positions([
            session("wb", day: 0, estimated: .sb, manual: .wb),
            session("none", day: 1, estimated: nil),
        ])
        #expect(result["none"] == .some(nil))
    }

    @Test func 診断の表記にWBが付くのはSBとWGだけ() {
        #expect(PlayingPosition.sb.diagnosisLabel == "SB（WB）")
        #expect(PlayingPosition.wg.diagnosisLabel == "WG（WB）")
        #expect(PlayingPosition.mf.diagnosisLabel == "MF")
        #expect(PlayingPosition.fw.diagnosisLabel == "FW")
    }
}

@MainActor
struct GrowthTrendEngineTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return c
    }

    private var reference: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 12))!
    }

    private func session(
        _ id: String,
        daysAgo: Double,
        distance: Double = 6000,
        duration: TimeInterval = 3600,
        position: PlayingPosition? = .mf,
        excluded: Bool = false,
        superseded: Bool = false
    ) -> TrainingSession {
        TrainingSession(
            id: id,
            userId: "u",
            date: reference.addingTimeInterval(-daysAgo * 86400),
            duration: duration,
            totalDistance: distance,
            excludeFromAverage: excluded ? true : nil,
            supersededBySplit: superseded ? true : nil,
            position: position,
            positionSource: position == nil ? nil : .manual
        )
    }

    @Test func 期間の境界ちょうどのセッションは含まれる() {
        let start = calendar.date(byAdding: .month, value: -1, to: reference)!
        let onBoundary = TrainingSession(id: "boundary", userId: "u", date: start, duration: 3600, totalDistance: 6000)
        let justBefore = TrainingSession(id: "before", userId: "u", date: start.addingTimeInterval(-1), duration: 3600, totalDistance: 6000)
        let result = GrowthTrendEngine.filteredSessions(
            [onBoundary, justBefore], period: .oneMonth, position: .all, reference: reference, calendar: calendar
        )
        #expect(result.map(\.id) == ["boundary"])
    }

    @Test func ポジションで絞り込める() {
        let sessions = [
            session("mf", daysAgo: 1, position: .mf),
            session("cb", daysAgo: 2, position: .cb),
            session("none", daysAgo: 3, position: nil),
        ]
        func ids(_ filter: GrowthTrendEngine.PositionFilter) -> Set<String> {
            Set(GrowthTrendEngine.filteredSessions(sessions, period: .threeMonths, position: filter, reference: reference, calendar: calendar).map(\.id))
        }
        #expect(ids(.all) == ["mf", "cb", "none"])
        #expect(ids(.position(.cb)) == ["cb"])
        #expect(ids(.unset) == ["none"])
    }

    @Test func 平均対象外のセッションはすべての集計から除かれる() {
        let sessions = [
            session("ok", daysAgo: 1),
            session("short", daysAgo: 2, duration: 200),
            session("excluded", daysAgo: 3, excluded: true),
            session("superseded", daysAgo: 4, superseded: true),
        ]
        let filtered = GrowthTrendEngine.filteredSessions(sessions, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(filtered.map(\.id) == ["ok"])
        let points = GrowthTrendEngine.trendPoints(sessions: sessions, metric: .distance, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(points.map(\.sessionId) == ["ok"])
    }

    @Test func 移動平均は3点目から5点の窓で計算される() {
        let averages = GrowthTrendEngine.movingAverages([1, 2, 3, 4, 5, 6])
        #expect(averages[0] == nil)
        #expect(averages[1] == nil)
        #expect(averages[2] == 2)
        #expect(averages[4] == 3)
        #expect(averages[5] == 4)
    }

    @Test func 自己ベストは有効値の中で一番高い記録1件だけ() {
        let sessions = [
            session("a", daysAgo: 4, distance: 6000),
            session("b", daysAgo: 3, distance: 7000),
            session("c", daysAgo: 2, distance: 6500),
            session("d", daysAgo: 1, distance: 7200),
        ]
        let best = GrowthTrendEngine.personalBest(sessions: sessions, metric: .distance, position: .all, until: reference)
        #expect(best?.sessionId == "d")
        let points = GrowthTrendEngine.trendPoints(sessions: sessions, metric: .distance, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(points.filter(\.isPersonalBest).map(\.sessionId) == ["d"])
    }

    @Test func 前半後半比較は6件以上で奇数なら真ん中を後半に含める() throws {
        let five = (0..<5).map { session("s\($0)", daysAgo: Double(10 - $0)) }
        #expect(GrowthTrendEngine.halfComparison(sessionsInPeriod: five, metric: .distance) == nil)

        let six = (0..<6).map { session("s\($0)", daysAgo: Double(10 - $0), distance: $0 < 3 ? 6000 : 7200) }
        let c6 = try #require(GrowthTrendEngine.halfComparison(sessionsInPeriod: six, metric: .distance))
        #expect(c6.firstAverage == 100)
        #expect(c6.secondAverage == 120)

        // 7件: 前半3件・後半4件
        let seven = (0..<7).map { session("s\($0)", daysAgo: Double(10 - $0), distance: $0 < 3 ? 6000 : 7200) }
        let c7 = try #require(GrowthTrendEngine.halfComparison(sessionsInPeriod: seven, metric: .distance))
        #expect(c7.firstAverage == 100)
        #expect(c7.secondAverage == 120)
    }

    @Test func 順位は同じ値を同順位にする() throws {
        let target = session("t", daysAgo: 0, distance: 6000)
        let comparisons = [
            session("a", daysAgo: 1, distance: 7200),
            session("b", daysAgo: 2, distance: 6000),
            session("c", daysAgo: 3, distance: 4800),
        ]
        let result = try #require(GrowthTrendEngine.todayComparison(target: target, comparisons: comparisons, metric: .distance))
        #expect(result.rank == 2)
        #expect(result.total == 4)
        #expect(result.average == 100)
    }

    @Test func 比較対象が3件未満ならデータ不足() {
        let target = session("t", daysAgo: 0)
        let comparisons = [session("a", daysAgo: 1), session("b", daysAgo: 2)]
        #expect(GrowthTrendEngine.todayComparison(target: target, comparisons: comparisons, metric: .distance) == nil)
    }

    @Test func 今日の出来は表示中のセッションより後と別ポジションを比較対象にしない() {
        let target = session("t", daysAgo: 5, position: .mf)
        let sessions = [
            target,
            session("before", daysAgo: 6, position: .mf),
            session("after", daysAgo: 1, position: .mf),
            session("otherPosition", daysAgo: 7, position: .cb),
        ]
        let ids = GrowthTrendEngine.comparisonSessions(for: target, in: sessions, period: .threeMonths, calendar: calendar).map(\.id)
        #expect(ids == ["before"])
    }

    @Test func 高さには自己ベストを付けない() {
        var s1 = session("a", daysAgo: 2); s1.avgPositionHeight = 40
        var s2 = session("b", daysAgo: 1); s2.avgPositionHeight = 60
        let points = GrowthTrendEngine.trendPoints(sessions: [s1, s2], metric: .height, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(points.allSatisfy { !$0.isPersonalBest })
    }

    private func speedSession(_ id: String, daysAgo: Double, kmh: Double, accuracy: Double) -> TrainingSession {
        var s = session(id, daysAgo: daysAgo)
        s.maxSpeed = kmh / 3.6
        s.gpsAccuracyMedian = accuracy
        return s
    }

    @Test func 最初の記録が一番高ければそれが自己ベスト() {
        let sessions = [
            session("first", daysAgo: 3, distance: 7200),
            session("b", daysAgo: 2, distance: 6000),
            session("c", daysAgo: 1, distance: 6500),
        ]
        let best = GrowthTrendEngine.personalBest(sessions: sessions, metric: .distance, position: .all, until: reference)
        #expect(best?.sessionId == "first")
        #expect(best?.value == 120)
    }

    @Test func 期間の外の自己ベストも返す() {
        let sessions = [
            session("old", daysAgo: 60, distance: 7200),
            session("recent", daysAgo: 1, distance: 6000),
        ]
        let best = GrowthTrendEngine.personalBest(sessions: sessions, metric: .distance, position: .all, until: reference)
        #expect(best?.sessionId == "old")
        let points = GrowthTrendEngine.trendPoints(sessions: sessions, metric: .distance, period: .oneMonth, position: .all, reference: reference, calendar: calendar)
        #expect(points.map(\.sessionId) == ["recent"])
        #expect(points.allSatisfy { !$0.isPersonalBest })
    }

    @Test func GPS精度の悪いセッションの最高速度は自己ベストに使わない() {
        let sessions = [
            speedSession("a", daysAgo: 3, kmh: 22, accuracy: 3),
            speedSession("b", daysAgo: 2, kmh: 25, accuracy: 3),
            speedSession("noisy", daysAgo: 1, kmh: 29, accuracy: 14),
        ]
        let points = GrowthTrendEngine.trendPoints(sessions: sessions, metric: .topSpeed, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(points.map(\.sessionId) == ["a", "b", "noisy"]) // 参考値もグラフには描く
        #expect(points.first(where: { $0.sessionId == "noisy" })?.isReferenceOnly == true)
        #expect(points.filter(\.isPersonalBest).map(\.sessionId) == ["b"])
    }

    @Test func GPS精度の悪いセッションは移動平均と比較に使わない() throws {
        let reliable = (0..<4).map { speedSession("r\($0)", daysAgo: Double(10 - $0), kmh: 20, accuracy: 3) }
        let noisy = speedSession("noisy", daysAgo: 1, kmh: 35, accuracy: 14)
        let points = GrowthTrendEngine.trendPoints(sessions: reliable + [noisy], metric: .topSpeed, period: .threeMonths, position: .all, reference: reference, calendar: calendar)
        #expect(points.first(where: { $0.sessionId == "noisy" })?.movingAverage == nil)
        #expect(points.compactMap(\.movingAverage).allSatisfy { abs($0 - 20) < 0.001 })

        // 今回が参考値なら比較しない。比較対象の参考値も使わない
        #expect(GrowthTrendEngine.todayComparison(target: noisy, comparisons: reliable, metric: .topSpeed) == nil)
        let target = speedSession("t", daysAgo: 0, kmh: 21, accuracy: 3)
        let result = try #require(GrowthTrendEngine.todayComparison(target: target, comparisons: reliable + [noisy], metric: .topSpeed))
        #expect(result.comparisonCount == 4)
        #expect(result.rank == 1)
    }

    @Test func GPS精度が悪くても最高速度以外の指標は通常どおり使う() {
        var s = session("noisy", daysAgo: 1)
        s.gpsAccuracyMedian = 14
        #expect(!GrowthTrendEngine.Metric.distance.isReferenceOnly(s))
        #expect(GrowthTrendEngine.Metric.topSpeed.isReferenceOnly(s))
    }

    @Test func パーセンタイルは線形補間() {
        #expect(GrowthTrendEngine.percentile(sortedValues: [0, 10, 20, 30, 40], 0.25) == 10)
        #expect(GrowthTrendEngine.percentile(sortedValues: [0, 10], 0.75) == 7.5)
    }
}
