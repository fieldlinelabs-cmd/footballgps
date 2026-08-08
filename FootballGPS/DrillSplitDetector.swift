//
//  DrillSplitDetector.swift
//  FootballGPS
//
//  ドリル自動分割（§セッション自動区切り）の休憩検知ロジック。
//  「登録済みフィールドの外＋低速度」が一定時間継続した区間を休憩とみなし、
//  1本の生GPSトレースを複数ドリルに分割するための境界を検出する。
//

import Foundation
import CoreLocation

enum DrillSplitConfig {
    /// フィールド外＋低速度がこの秒数以上継続したら「本物の休憩」と確定する（調整可能）
    static let minBenchDwellDuration: TimeInterval = 60
    /// 休憩判定に使う低速度しきい値（m/s）
    static let lowSpeedThreshold: Double = 1.0
    /// 分割後の1本が短すぎて無意味にならないための最小セグメント長（秒）
    static let minSegmentDuration: TimeInterval = 60
}

// DrillBreakInterval は TrainingSession.pendingSplitBreaks の型として
// Watchアプリターゲットとも共有する必要があるため ModelsTrainingSession.swift 側に定義

enum DrillSplitDetector {

    /// GPS点列とフィールドから休憩区間を検出する（純粋関数）
    static func detectBreaks(points: [GPSPoint], field: Field) -> [DrillBreakInterval] {
        guard let first = points.first, points.count >= 2 else { return [] }

        var breaks: [DrillBreakInterval] = []
        var breakStartOffset: TimeInterval? = nil

        func isOutsideLowSpeed(_ point: GPSPoint) -> Bool {
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            return !field.contains(coordinate: coordinate) && point.speed < DrillSplitConfig.lowSpeedThreshold
        }

        for point in points {
            let offset = point.timestamp.timeIntervalSince(first.timestamp)
            let outside = isOutsideLowSpeed(point)

            if let start = breakStartOffset {
                if !outside {
                    // フィールドに戻る or 速度が上がった → 休憩終了。継続時間が閾値以上なら確定
                    if offset - start >= DrillSplitConfig.minBenchDwellDuration {
                        breaks.append(DrillBreakInterval(startOffset: start, endOffset: offset))
                    }
                    breakStartOffset = nil
                }
                // outside が継続中なら何もしない（滞留継続）
            } else if outside {
                breakStartOffset = offset
            }
        }

        // トレース終了まで休憩状態が続いていた場合（練習終了時点でフィールド外にいたまま終了）
        if let start = breakStartOffset, let last = points.last {
            let endOffset = last.timestamp.timeIntervalSince(first.timestamp)
            if endOffset - start >= DrillSplitConfig.minBenchDwellDuration {
                breaks.append(DrillBreakInterval(startOffset: start, endOffset: endOffset))
            }
        }

        return breaks
    }

    /// 休憩区間から、ドリル本編とみなせる区間（[start, end)）を返す。
    /// 休憩の直前直後にできる短すぎる断片（`minSegmentDuration`未満）は捨てる。
    static func segmentRanges(
        totalDuration: TimeInterval,
        breaks: [DrillBreakInterval]
    ) -> [(start: TimeInterval, end: TimeInterval)] {
        guard !breaks.isEmpty else { return [] }

        var ranges: [(start: TimeInterval, end: TimeInterval)] = []
        var cursor: TimeInterval = 0
        for brk in breaks {
            if brk.startOffset - cursor >= DrillSplitConfig.minSegmentDuration {
                ranges.append((start: cursor, end: brk.startOffset))
            }
            cursor = brk.endOffset
        }
        if totalDuration - cursor >= DrillSplitConfig.minSegmentDuration {
            ranges.append((start: cursor, end: totalDuration))
        }
        return ranges
    }
}
