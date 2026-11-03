//
//  SessionReflectionTests.swift
//  FootballGPSTests
//
//  振り返り（機能仕様書 §9.7）の確認
//

import Testing
import Foundation
@testable import FootballGPS

struct SessionReflectionTests {

    @Test func 何も書かれていなければ保存しない() {
        #expect(SessionReflection().normalized == nil)
        #expect(SessionReflection(memo: "  \n ").normalized == nil)
    }

    @Test func メモの前後の空白を除く() {
        #expect(SessionReflection(memo: "  右に寄った\n").normalized?.memo == "右に寄った")
    }

    @Test func タグだけでも保存する() {
        let reflection = SessionReflection(opponent: .stronger, memo: " ").normalized
        #expect(reflection?.opponent == .stronger)
        #expect(reflection?.memo == nil)
    }

    @Test func タグを読める形に並べる() {
        let reflection = SessionReflection(opponent: .stronger, result: .loss, condition: .good, weather: .rainy)
        #expect(reflection.tagLabels == ["相手: 強い", "負け", "体調: 良い", "雨"])
    }

    @Test func 振り返りのない古い記録を読み込める() throws {
        var session = TrainingSession(userId: "user")
        session.reflection = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(session)
        #expect(!String(decoding: data, as: UTF8.self).contains("reflection"))
        #expect(try decoder.decode(TrainingSession.self, from: data).reflection == nil)
    }

    @Test func 振り返りを保存して読み戻せる() throws {
        var session = TrainingSession(userId: "user")
        session.reflection = SessionReflection(result: .win, weather: .windy, memo: "風下で押し込めた")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(TrainingSession.self, from: encoder.encode(session))
        #expect(decoded.reflection == session.reflection)
    }
}
