//
//  SessionCompareTests.swift
//  FootballGPSTests
//
//  2回を比べる画面（機能仕様書 §9.6）の比較先の選び方の確認
//

import Testing
import Foundation
@testable import FootballGPS

struct SessionCompareTests {

    private func session(
        id: String,
        at day: Double,
        position: PlayingPosition? = .mf,
        fieldId: String? = "field",
        duration: TimeInterval = 600,
        excludeFromAverage: Bool? = nil,
        supersededBySplit: Bool? = nil,
        splitFromSessionId: String? = nil
    ) -> TrainingSession {
        TrainingSession(
            id: id,
            userId: "user",
            fieldId: fieldId,
            date: Date(timeIntervalSince1970: day * 86400),
            duration: duration,
            excludeFromAverage: excludeFromAverage,
            supersededBySplit: supersededBySplit,
            splitFromSessionId: splitFromSessionId,
            position: position
        )
    }

    @Test func 候補は対象外の記録を除いて新しい順になる() {
        let target = session(id: "target", at: 5)
        let sessions = [
            target,
            session(id: "old", at: 1),
            session(id: "new", at: 9),
            session(id: "excluded", at: 2, excludeFromAverage: true),
            session(id: "short", at: 3, duration: 200),
            session(id: "superseded", at: 4, supersededBySplit: true),
            session(id: "noField", at: 6, fieldId: nil),
        ]
        let candidates = GrowthTrendEngine.comparisonCandidates(for: target, in: sessions)
        #expect(candidates.map(\.id) == ["new", "old"])
    }

    @Test func 初期値は同じポジションの直前のセッション() {
        let target = session(id: "target", at: 5, position: .mf)
        let candidates = [
            session(id: "later", at: 9, position: .mf),
            session(id: "otherPosition", at: 4, position: .fw),
            session(id: "previous", at: 3, position: .mf),
            session(id: "older", at: 1, position: .mf),
        ]
        #expect(GrowthTrendEngine.defaultComparison(for: target, candidates: candidates)?.id == "previous")
    }

    @Test func 同じ元記録のドリルは初期値にしない() {
        let target = session(id: "target", at: 5, splitFromSessionId: "match")
        let candidates = [
            session(id: "sameMatch", at: 4.9, splitFromSessionId: "match"),
            session(id: "previous", at: 3),
        ]
        #expect(GrowthTrendEngine.defaultComparison(for: target, candidates: candidates)?.id == "previous")
    }

    @Test func 同じポジションがなければ直前のセッションになる() {
        let target = session(id: "target", at: 5, position: .mf)
        let candidates = [session(id: "previous", at: 3, position: .fw)]
        #expect(GrowthTrendEngine.defaultComparison(for: target, candidates: candidates)?.id == "previous")
    }

    @Test func ポジションが未設定なら絞らない() {
        let target = session(id: "target", at: 5, position: nil)
        let candidates = [session(id: "previous", at: 3, position: .fw)]
        #expect(GrowthTrendEngine.defaultComparison(for: target, candidates: candidates)?.id == "previous")
    }

    @Test func 自分より前がなければ候補の先頭になる() {
        let target = session(id: "target", at: 5)
        let candidates = [session(id: "newest", at: 9), session(id: "later", at: 7)]
        #expect(GrowthTrendEngine.defaultComparison(for: target, candidates: candidates)?.id == "newest")
    }

    @Test func 候補がなければ初期値もない() {
        #expect(GrowthTrendEngine.defaultComparison(for: session(id: "target", at: 5), candidates: []) == nil)
    }
}
