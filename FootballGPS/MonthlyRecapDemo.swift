//
//  MonthlyRecapDemo.swift
//  FootballGPS
//
//  開発者ツール「サンプルでまとめを見る」（技術実装仕様書 §27.8）。Debugビルドのみ。
//  架空のセッションをメモリ上だけで作ってストーリーを再生する。実際のデータには保存しない
//

#if DEBUG
import Foundation
import CoreGraphics

enum MonthlyRecapDemo {
    /// 先月を対象に、その前の月の記録も含めた2か月分の架空のセッションでまとめを作る。
    /// クイズ・継続・自己ベスト・最速のスプリント・積み上がるヒートマップがすべて出る内容にする
    static func make(now: Date = Date()) -> (recap: MonthlyRecap, preset: MonthlyRecapPreset)? {
        let month = RecapMonth(date: now).previous
        let calendar = Calendar.current
        func date(_ month: RecapMonth, _ day: Int, hour: Int = 10) -> Date {
            calendar.date(from: DateComponents(year: month.year, month: month.month, day: day, hour: hour)) ?? now
        }
        func session(_ date: Date, minutes: Double, distance: Double, maxSpeed: Double, sprints: Int, position: PlayingPosition) -> TrainingSession {
            TrainingSession(
                userId: "demo", date: date, duration: minutes * 60,
                totalDistance: distance, maxSpeed: maxSpeed, sprintCount: sprints,
                position: position, gpsAccuracyMedian: 3
            )
        }

        // 前の月: 毎週末にプレー（自己ベストの比較と継続の数え始めに使う）
        let previous = month.previous
        let previousSessions = [6, 13, 20, 27].map {
            session(date(previous, $0), minutes: 60, distance: 5600, maxSpeed: 7.0, sprints: 11, position: .mf)
        }
        // 対象の月: 毎週プレーし、1日は午前と夕方の2回（日ごとの合計の確認用）。終盤に自己ベストを更新する
        let plays: [(day: Int, hour: Int, distance: Double, maxSpeed: Double, sprints: Int, position: PlayingPosition)] = [
            (3, 10, 5900, 7.1, 12, .mf), (7, 19, 4800, 6.8, 9, .mf), (10, 10, 6400, 7.2, 13, .mf),
            (14, 10, 3100, 6.6, 6, .fw), (14, 18, 3300, 7.0, 8, .fw), (17, 10, 6900, 7.4, 15, .mf),
            (21, 19, 5200, 6.9, 10, .mf), (24, 10, 7350, 7.6, 17, .mf), (28, 10, 6100, 7.3, 14, .mf),
        ]
        let currentSessions = plays.map {
            session(date(month, $0.day, hour: $0.hour), minutes: 60, distance: $0.distance, maxSpeed: $0.maxSpeed, sprints: $0.sprints, position: $0.position)
        }

        guard let recap = MonthlyRecapEngine.recap(
            for: month, sessions: previousSessions + currentSessions, playerCategory: .general
        ) else { return nil }

        // ヒートマップ: 架空のGPSの点を日ごとに積み上げる（MonthlyRecapEngine.heatmapFrames と同じ正規化）
        let rows = RecapHeatmapView.rows, cols = RecapHeatmapView.cols
        let days = Array(Set(recap.sessions.map { calendar.startOfDay(for: $0.date) })).sorted()
        var accumulated = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        var rawFrames: [(Date, [[Double]])] = []
        for (i, day) in days.enumerated() {
            let gps = MockData.generateMockGPSData(sessionId: "demo-\(i)", pointCount: 250)
            let points = HeatmapGrid.normalizedPoints(gps.points, field: MockData.mockField, isFlipped: false)
            let raw = HeatmapGrid.rawGrid(normalizedPoints: points, rows: rows, cols: cols)
            for r in 0..<rows { for c in 0..<cols { accumulated[r][c] += raw[r][c] } }
            rawFrames.append((day, accumulated))
        }
        let maxValue = rawFrames.last?.1.flatMap { $0 }.max() ?? 0
        let frames = rawFrames.map { HeatmapFrame(day: $0.0, grid: HeatmapGrid.normalized($0.1, maxValue: maxValue)) }

        // 最速のスプリント: 自陣の右寄りから斜めに駆け上がる軌跡
        let pathCount = 16
        let path = (0..<pathCount).map { i -> CGPoint in
            let t = Double(i) / Double(pathCount - 1)
            return CGPoint(x: 0.72 - t * 0.22 + sin(t * .pi) * 0.04, y: 0.30 + t * 0.30)
        }
        let speeds = (0..<pathCount).map { i -> Double in
            let t = Double(i) / Double(pathCount - 1)
            return 3 + 4.6 * sin(t * .pi * 0.9)
        }
        let sprint = SprintReplay(
            date: date(month, 24), maxSpeed: speeds.max() ?? 7.6, distance: 34, duration: 4.4,
            path: path, speeds: speeds, sprintStart: 4, sprintEnd: 12
        )

        let bestGPS = MockData.generateMockGPSData(sessionId: "demo-best", pointCount: 600)
        let bestGrid = HeatmapGrid.compute(
            normalizedPoints: HeatmapGrid.normalizedPoints(bestGPS.points, field: MockData.mockField, isFlipped: false),
            rows: rows, cols: cols
        )

        return (recap, MonthlyRecapPreset(bestGrid: bestGrid, heatmapFrames: frames, sprintReplay: sprint))
    }
}
#endif
