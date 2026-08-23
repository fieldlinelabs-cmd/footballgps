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
    /// フィールド外での休憩中、GPSノイズや一瞬の動きで低速度条件を満たさない点が
    /// 挟まっても、直前の適合点からこの秒数以内なら休憩が継続しているとみなす（調整可能）
    static let interruptionTolerance: TimeInterval = 15
}

// DrillBreakInterval は TrainingSession.pendingSplitBreaks の型として
// Watchアプリターゲットとも共有する必要があるため ModelsTrainingSession.swift 側に定義

enum DrillSplitDetector {

    /// GPS点列とフィールドから休憩区間を検出する（純粋関数）。
    ///
    /// フィールドに最初に入った時刻より前、および最後にフィールド内にいた時刻より後は、
    /// 速度に関わらず無条件で休憩（＝ドリルではない移動時間）とみなす。コーチが実際に
    /// フィールドへ向かう・フィールドから帰る移動は、普通の速さ（低速度しきい値超）で
    /// 行われることが多く、フィールド在中区間と同じ「低速度」条件を適用すると、この移動
    /// 時間が誤って独立した1本のドリルとして検出されてしまうため。
    /// フィールド在中区間の内部でのみ、これまで通り「外＋低速度60秒」で休憩を検出する
    /// （一瞬フィールド境界をまたいだだけか、本当の休憩かの曖昧さがあるため速度判定が必要）。
    static func detectBreaks(points: [GPSPoint], field: Field) -> [DrillBreakInterval] {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return [] }

        func offset(of point: GPSPoint) -> TimeInterval {
            point.timestamp.timeIntervalSince(first.timestamp)
        }
        func isInsideField(_ point: GPSPoint) -> Bool {
            field.contains(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }

        guard let firstInsideIndex = points.firstIndex(where: isInsideField),
              let lastInsideIndex = points.lastIndex(where: isInsideField) else {
            return []
        }
        let fieldEntryOffset = offset(of: points[firstInsideIndex])
        let fieldExitOffset = offset(of: points[lastInsideIndex])
        let totalDuration = offset(of: last)

        var breaks: [DrillBreakInterval] = []

        // フィールドに入る前の移動時間は速度に関わらず無条件で除外する
        if fieldEntryOffset > 0 {
            breaks.append(DrillBreakInterval(startOffset: 0, endOffset: fieldEntryOffset))
        }

        // フィールド在中区間でのみ、外＋低速度60秒の休憩検出を行う。
        // フィールドに戻った場合は即座に休憩終了（現在時刻で確定）とする一方、
        // フィールド外のまま速度だけ一瞬上がった場合は、GPSノイズや小さな動きの
        // 可能性があるため、直前の適合点からinterruptionTolerance以内なら
        // 休憩が継続しているとみなし、リセットしない
        func isOutsideLowSpeed(_ point: GPSPoint) -> Bool {
            !isInsideField(point) && point.speed < DrillSplitConfig.lowSpeedThreshold
        }

        var breakStartOffset: TimeInterval? = nil
        var lastQualifyingOffset: TimeInterval? = nil

        for point in points[firstInsideIndex...lastInsideIndex] {
            let currentOffset = offset(of: point)
            let inside = isInsideField(point)
            let outside = isOutsideLowSpeed(point)

            if outside {
                if breakStartOffset == nil {
                    breakStartOffset = currentOffset
                }
                lastQualifyingOffset = currentOffset
            } else if inside {
                // フィールドに戻った → 中断許容とは関係なく即座に休憩終了、現在時刻で確定判定
                if let start = breakStartOffset, currentOffset - start >= DrillSplitConfig.minBenchDwellDuration {
                    breaks.append(DrillBreakInterval(startOffset: start, endOffset: currentOffset))
                }
                breakStartOffset = nil
                lastQualifyingOffset = nil
            } else if let start = breakStartOffset, let lastQualifying = lastQualifyingOffset,
                      currentOffset - lastQualifying > DrillSplitConfig.interruptionTolerance {
                // フィールド外のまま、直前の適合点から許容時間を超えて速度が高い状態が続いた
                // → 中断とみなし、直前の適合点までを休憩として確定判定
                if lastQualifying - start >= DrillSplitConfig.minBenchDwellDuration {
                    breaks.append(DrillBreakInterval(startOffset: start, endOffset: lastQualifying))
                }
                breakStartOffset = nil
                lastQualifyingOffset = nil
            }
            // 許容範囲内の中断（フィールド外・速度高いが直近の適合点からtolerance以内）ならそのまま継続
        }

        // フィールドを出た後の移動時間も速度に関わらず無条件で除外する
        if fieldExitOffset < totalDuration {
            breaks.append(DrillBreakInterval(startOffset: fieldExitOffset, endOffset: totalDuration))
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
