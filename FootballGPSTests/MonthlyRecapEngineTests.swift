//
//  MonthlyRecapEngineTests.swift
//  FootballGPSTests
//
//  月ごとのまとめの集計（docs/技術実装仕様書.md §27.2・§27.3）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct MonthlyRecapEngineTests {

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 10))!
    }

    private func session(
        _ date: Date, minutes: Double = 60, distance: Double = 6000, maxSpeed: Double = 7,
        sprints: Int = 10, position: PlayingPosition? = nil, lowAccuracy: Bool = false
    ) -> TrainingSession {
        TrainingSession(
            userId: "u", date: date, duration: minutes * 60,
            totalDistance: distance, maxSpeed: maxSpeed, sprintCount: sprints,
            position: position, gpsAccuracyMedian: lowAccuracy ? 14 : 3
        )
    }

    @Test func 終わった月で3回以上の月だけを新しい順に返す() {
        let sessions = [
            session(date(2026, 8, 1)), session(date(2026, 8, 8)), session(date(2026, 8, 15)),
            session(date(2026, 9, 1)), session(date(2026, 9, 8)),                               // 2回だけ
            session(date(2026, 10, 1)), session(date(2026, 10, 8)), session(date(2026, 10, 15)), // 今月
        ]
        let months = MonthlyRecapEngine.availableMonths(sessions: sessions, now: date(2026, 10, 20))
        #expect(months == [RecapMonth(year: 2026, month: 8)])
    }

    @Test func 五分未満のセッションは数えない() {
        let sessions = [
            session(date(2026, 8, 1)), session(date(2026, 8, 8)), session(date(2026, 8, 15), minutes: 4),
        ]
        #expect(MonthlyRecapEngine.availableMonths(sessions: sessions, now: date(2026, 10, 1)).isEmpty)
    }

    @Test func 合計と精度の低い記録を除いた最高速度() throws {
        let sessions = [
            session(date(2026, 8, 1), distance: 5000, maxSpeed: 7, sprints: 5),
            session(date(2026, 8, 8), distance: 6000, maxSpeed: 9, sprints: 7, lowAccuracy: true),
            session(date(2026, 8, 15), distance: 7000, maxSpeed: 8, sprints: 9),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        #expect(recap.sessionCount == 3)
        #expect(recap.totalDistance == 18000)
        #expect(recap.totalSprints == 21)
        #expect(recap.bestMaxSpeed == 8)
        #expect(!recap.hasComparison)
    }

    @Test func 先月との比較は5パーセント以内を維持とする() throws {
        let sessions = [
            // 7月: 1分あたり100m、最高速度 7m/s、1回あたり10回
            session(date(2026, 7, 1), distance: 6000, maxSpeed: 7, sprints: 10),
            // 8月: 1分あたり103m（維持）、最高速度 8m/s（伸びた）、1回あたり8回（下がった）
            session(date(2026, 8, 1), distance: 6180, maxSpeed: 8, sprints: 8),
            session(date(2026, 8, 8), distance: 6180, maxSpeed: 7, sprints: 8),
            session(date(2026, 8, 15), distance: 6180, maxSpeed: 7, sprints: 8),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        #expect(recap.distancePerMinute?.direction == .kept)
        #expect(recap.maxSpeed?.direction == .up)
        #expect(recap.sprintsPerSession?.direction == .down)
    }

    @Test func 最も多いポジション() throws {
        let sessions = [
            session(date(2026, 8, 1), position: .mf), session(date(2026, 8, 8), position: .fw),
            session(date(2026, 8, 15), position: .mf),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        #expect(recap.topPosition == .mf)
    }

    @Test func ルールで作る二つ名() {
        #expect(MonthlyRecapEngine.ruleNickname(position: .mf, playerType: .speedster) == "中盤のスピードスター")
        #expect(MonthlyRecapEngine.ruleNickname(position: .fw, playerType: .stamina) == "最前線の鉄人")
        #expect(MonthlyRecapEngine.ruleNickname(position: nil, playerType: .agile) == "ピッチのキレ者")
    }

    @Test func 二つ名は一番よかったセッションのものを優先しその月のセッション以外は使わない() throws {
        let sessions = [
            session(date(2026, 8, 1), distance: 4000), session(date(2026, 8, 8), distance: 9000),
            session(date(2026, 8, 15), distance: 5000),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        func row(_ name: String, session: String?, day: Int) -> NicknameRow {
            NicknameRow(id: UUID(), nickname: name, reason: "", createdAt: date(2026, 9, day), localSessionId: session)
        }
        let other = sessions.first { $0.id != recap.bestSession.id }!.id

        // 一番よかったセッションの二つ名があれば、より新しい他のセッションの二つ名より優先する
        let withBest = [row("最新の別セッション", session: other, day: 20), row("ベストの二つ名", session: recap.bestSession.id, day: 10)]
        #expect(MonthlyRecapEngine.pickNickname(withBest, recap: recap) == "ベストの二つ名")

        // なければ、その月のセッションの二つ名で一番新しいもの。月の外のセッションの二つ名は使わない
        let withoutBest = [row("古い", session: other, day: 2), row("月の外", session: "outside", day: 25), row("新しい", session: other, day: 12)]
        #expect(MonthlyRecapEngine.pickNickname(withoutBest, recap: recap) == "新しい")

        #expect(MonthlyRecapEngine.pickNickname([row("月の外", session: "outside", day: 25)], recap: recap) == nil)
    }

    @Test func よく走った日は同じ日のセッションを合計し0mの日を除く() throws {
        let morning = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!
        let evening = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 18))!
        let sessions = [
            session(morning, distance: 1200), session(evening, distance: 1000),
            session(date(2026, 8, 8), distance: 1500),
            session(date(2026, 8, 23), distance: 0),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        let days = recap.dailyDistances
        #expect(days.map(\.distance) == [2200, 1500])
        #expect(Calendar.current.component(.day, from: days[0].day) == 11)
    }

    @Test func クイズは1位2位最下位の3択で正解の位置が正しい() throws {
        let sessions = [
            session(date(2026, 8, 3), distance: 5000), session(date(2026, 8, 9), distance: 7000),
            session(date(2026, 8, 14), distance: 6500), session(date(2026, 8, 22), distance: 7400),
        ]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        let quiz = try #require(recap.quiz)
        #expect(Set(quiz.options.map(\.distance)) == [7400, 7000, 5000])
        #expect(quiz.options[quiz.correctIndex].distance == 7400)
    }

    @Test func 継続は前の月からの週も数える() {
        // 7月27日（月）の週、8月3日の週、8月10日の週に続けてプレー。8月17日の週はなし、8月24日の週にプレー
        let sessions = [
            session(date(2026, 7, 28)), session(date(2026, 8, 4)), session(date(2026, 8, 12)),
        ]
        #expect(MonthlyRecapEngine.weeklyStreak(endingIn: RecapMonth(year: 2026, month: 8), sessions: sessions) == 3)
        let withGap = sessions + [session(date(2026, 8, 25))]
        #expect(MonthlyRecapEngine.weeklyStreak(endingIn: RecapMonth(year: 2026, month: 8), sessions: withGap) == 1)
    }

    @Test func 自己ベストは前の月までの記録を超えたものだけで初めての月は出さない() {
        let july = [session(date(2026, 7, 10), distance: 6000, maxSpeed: 8, sprints: 12)]
        let august = [
            session(date(2026, 8, 1), distance: 7000, maxSpeed: 7, sprints: 10),
            session(date(2026, 8, 8), distance: 5000, maxSpeed: 9, sprints: 11, lowAccuracy: true),
        ]
        let bests = MonthlyRecapEngine.personalBests(in: RecapMonth(year: 2026, month: 8), sessions: july + august)
        // 距離だけが更新。最高速度の9m/sは精度が低い記録なので数えない
        #expect(bests.map(\.title) == ["1回の走行距離"])
        #expect(MonthlyRecapEngine.personalBests(in: RecapMonth(year: 2026, month: 8), sessions: august).isEmpty)
    }

    @Test func 開発者ツールのサンプルはすべての画面が出る内容になっている() throws {
        let demo = try #require(MonthlyRecapDemo.make(now: date(2026, 10, 29)))
        #expect(demo.recap.month == RecapMonth(year: 2026, month: 9))
        #expect(demo.recap.quiz != nil)
        #expect(demo.recap.weeklyStreak >= 2)
        #expect(!demo.recap.personalBests.isEmpty)
        #expect(demo.recap.hasComparison)
        #expect(demo.recap.dailyDistances.count < demo.recap.sessionCount)  // 同じ日に2回ある
        #expect(demo.preset.sprintReplay != nil)
        #expect((demo.preset.heatmapFrames?.count ?? 0) > 1)
    }

    @Test func よくプレーした時間帯は最も多い時間帯とその中で最も多い時刻() throws {
        let cal = Calendar.current
        func at(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))! }
        let sessions = [session(at(1, 19)), session(at(2, 19)), session(at(3, 20)), session(at(4, 7))]
        let recap = try #require(MonthlyRecapEngine.recap(for: RecapMonth(year: 2026, month: 8), sessions: sessions, playerCategory: .general))
        let time = try #require(recap.timeOfDay)
        #expect(time.band == .night)
        #expect(time.peakHour == 19)
        #expect(RecapTimeBand.band(forHour: 6) == .morning)
        #expect(RecapTimeBand.band(forHour: 16) == .evening)
    }

    @Test func 軌跡の間引きは点の数を上限までにし最初と最後の点を残す() {
        let points = (0..<1001).map { CGPoint(x: Double($0), y: 0) }
        let thinned = MonthlyRecapEngine.thinned(points, maxPoints: 100)
        #expect(thinned.count == 100)
        #expect(thinned.first == points.first)
        #expect(thinned.last == points.last)
        #expect(MonthlyRecapEngine.thinned(Array(points.prefix(50)), maxPoints: 100).count == 50)
    }

    @Test func 月の前後() {
        #expect(RecapMonth(year: 2026, month: 1).previous == RecapMonth(year: 2025, month: 12))
        #expect(RecapMonth(year: 2026, month: 12).next == RecapMonth(year: 2027, month: 1))
        #expect(RecapMonth(year: 2026, month: 3).id == "2026-03")
    }
}
