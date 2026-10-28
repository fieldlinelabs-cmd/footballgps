//
//  GrowthTrendEngine.swift
//  FootballGPS
//
//  統計推移（docs/統計推移仕様書.md）の集計ロジック。推移画面・今日の出来カードの計算を
//  すべて [TrainingSession] を受け取る static 関数に集約し、UI から切り離してテストできるようにする。
//  新しい永続化ストアは持たない（PlayerDataEngine と同じ方針）。

import Foundation

enum GrowthTrendEngine {

    // MARK: - 期間・ポジション・指標

    enum Period: Int, CaseIterable, Identifiable {
        case oneMonth = 1
        case threeMonths = 3
        case sixMonths = 6
        case twelveMonths = 12

        var id: Int { rawValue }
        var label: String { "\(rawValue)M" }
        var longLabel: String { "過去\(rawValue)ヶ月" }

        /// 基準日時から rawValue ヶ月前（カレンダーの月単位）
        func startDate(from reference: Date, calendar: Calendar = .current) -> Date {
            calendar.date(byAdding: .month, value: -rawValue, to: reference) ?? reference
        }
    }

    /// ポジションでの絞り込み。rawValue は @AppStorage 保存用
    enum PositionFilter: Hashable, Identifiable {
        case all
        case position(PlayingPosition)
        case unset

        static var allCases: [PositionFilter] {
            [.all] + PlayingPosition.allCases.map { .position($0) } + [.unset]
        }

        var id: String { rawValue }

        var rawValue: String {
            switch self {
            case .all: return "all"
            case .unset: return "unset"
            case .position(let p): return p.rawValue
            }
        }

        init(rawValue: String) {
            switch rawValue {
            case "unset": self = .unset
            default: self = PlayingPosition(rawValue: rawValue).map { .position($0) } ?? .all
            }
        }

        var label: String {
            switch self {
            case .all: return "すべて"
            case .unset: return "未設定"
            case .position(let p): return p.displayName
            }
        }

        func matches(_ session: TrainingSession) -> Bool {
            switch self {
            case .all: return true
            case .unset: return session.position == nil
            case .position(let p): return session.position == p
            }
        }
    }

    enum Metric: String, CaseIterable, Identifiable {
        case distance, sprint, agility, topSpeed, intensity, stamina, height

        var id: String { rawValue }

        var label: String {
            switch self {
            case .distance:  return "走力"
            case .sprint:    return "スプリント"
            case .agility:   return "アジリティ"
            case .topSpeed:  return "最高速度"
            case .intensity: return "高強度"
            case .stamina:   return "スタミナ"
            case .height:    return "立ち位置"
            }
        }

        /// グラフや説明で使う、少し詳しい名前
        var detailLabel: String {
            switch self {
            case .distance:  return "走力（1分あたりの距離）"
            case .sprint:    return "スプリント（10分あたり）"
            case .agility:   return "アジリティ（10分あたり）"
            case .topSpeed:  return "最高速度"
            case .intensity: return "高強度（心拍の高強度割合）"
            case .stamina:   return "スタミナ（後半の運動量の維持率）"
            case .height:    return "立ち位置（ポジションの高さ）"
            }
        }

        var unit: String {
            switch self {
            case .distance:  return "m/分"
            case .sprint, .agility: return "回/10分"
            case .topSpeed:  return "km/h"
            case .intensity, .stamina, .height: return "%"
            }
        }

        /// GPS 精度の悪いセッションでは参考値として扱う指標か（§10.1）。誤差が直接値を押し上げる最高速度だけ
        var isAffectedByLowGPSAccuracy: Bool { self == .topSpeed }

        /// このセッションのこの指標が参考値か。参考値はグラフに描くが、移動平均・自己ベスト・
        /// 成長サマリー・今日の出来の比較には使わない
        func isReferenceOnly(_ session: TrainingSession) -> Bool {
            isAffectedByLowGPSAccuracy && session.isLowGPSAccuracy
        }

        /// 比較・集計に使ってよい値（参考値なら nil）
        func reliableValue(for session: TrainingSession) -> Double? {
            isReferenceOnly(session) ? nil : value(for: session)
        }

        /// 高いほど良い指標か。「高さ」はポジションによって望ましい値が違うため、
        /// 順位・自己ベスト・良し悪しの色を付けない（§6.4）
        var hasDirection: Bool { self != .height }

        func format(_ value: Double) -> String {
            switch self {
            case .distance, .intensity, .stamina, .height: return String(format: "%.0f", value)
            case .sprint, .agility, .topSpeed: return String(format: "%.1f", value)
            }
        }

        /// セッションの指標値。値がない（計算できない）セッションは nil。
        /// 「立ち位置」は平均の高さを返す（最前線・最低線の高さは TrendPoint.frontHeight / backHeight）
        func value(for session: TrainingSession) -> Double? {
            let minutes = session.duration / 60.0
            switch self {
            case .distance:
                return minutes > 0 ? session.totalDistance / minutes : nil
            case .sprint:
                guard minutes > 0, let count = session.sprintCount else { return nil }
                return Double(count) / minutes * 10
            case .agility:
                guard minutes > 0, let count = session.agilityTurnCount else { return nil }
                return Double(count) / minutes * 10
            case .topSpeed:
                return session.maxSpeed * 3.6
            case .intensity:
                return session.hrIntensityRatio
            case .stamina:
                return session.staminaDrop.map { $0 * 100 }
            case .height:
                return session.avgPositionHeight
            }
        }
    }

    // MARK: - 絞り込み（§10）

    /// 集計対象（PlayerDataEngine.eligibleSessions と同じ除外規約）のうち、
    /// ポジション条件に合い、[期間の開始, 基準日時] に入るものを日付の昇順で返す。
    /// includeReference = false なら基準日時ちょうどのセッションを含めない（今日の出来カード用）
    static func filteredSessions(
        _ sessions: [TrainingSession],
        period: Period,
        position: PositionFilter,
        reference: Date,
        includeReference: Bool = true,
        calendar: Calendar = .current
    ) -> [TrainingSession] {
        let start = period.startDate(from: reference, calendar: calendar)
        return PlayerDataEngine.eligibleSessions(sessions)
            .filter { position.matches($0) }
            .filter { $0.date >= start && (includeReference ? $0.date <= reference : $0.date < reference) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - 推移グラフ（§8.3）

    struct TrendPoint: Identifiable {
        let sessionId: String
        let date: Date
        let value: Double
        let frontHeight: Double?   // 「立ち位置」のときだけ、最前線の高さ
        let backHeight: Double?    // 「立ち位置」のときだけ、最低線の高さ
        let duration: TimeInterval
        let movingAverage: Double?
        let isPersonalBest: Bool
        let isReferenceOnly: Bool  // GPS 精度の悪いセッションの参考値（§10.1）

        var id: String { sessionId }
    }

    static let movingAverageWindow = 5
    static let movingAverageMinCount = 3

    /// 直近 window 件の移動平均。minCount 件たまるまでは nil
    static func movingAverages(_ values: [Double], window: Int = movingAverageWindow, minCount: Int = movingAverageMinCount) -> [Double?] {
        values.indices.map { i in
            guard i + 1 >= minCount else { return nil }
            let slice = values[max(0, i - window + 1)...i]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    /// 推移グラフの点。自己ベストは「選んだポジション条件の中で、その時点までの全期間の自己ベストを更新したか」
    static func trendPoints(
        sessions: [TrainingSession],
        metric: Metric,
        period: Period,
        position: PositionFilter,
        reference: Date = Date(),
        calendar: Calendar = .current
    ) -> [TrendPoint] {
        let inPeriod = filteredSessions(sessions, period: period, position: position, reference: reference, calendar: calendar)
        let valued = inPeriod.compactMap { s in metric.value(for: s).map { (session: s, value: $0) } }
        // 移動平均は参考値を除いた点だけで計算し、参考値の点には線を引かない
        let reliable = valued.filter { !metric.isReferenceOnly($0.session) }
        let reliableAverages = movingAverages(reliable.map(\.value))
        let averageById = Dictionary(uniqueKeysWithValues: zip(reliable.map(\.session.id), reliableAverages))

        let bestId = personalBest(sessions: sessions, metric: metric, position: position, until: reference)?.sessionId

        return valued.map { item in
            TrendPoint(
                sessionId: item.session.id,
                date: item.session.date,
                value: item.value,
                frontHeight: metric == .height ? item.session.frontPositionHeight : nil,
                backHeight: metric == .height ? item.session.backPositionHeight : nil,
                duration: item.session.duration,
                movingAverage: averageById[item.session.id] ?? nil,
                isPersonalBest: item.session.id == bestId,
                isReferenceOnly: metric.isReferenceOnly(item.session)
            )
        }
    }

    struct PersonalBest {
        let sessionId: String
        let date: Date
        let value: Double
    }

    /// 選んだポジション条件の中で、基準日時までの全期間の自己ベスト（有効値の中で一番高い記録。同じ値なら古い方）。
    /// 参考値（GPS 精度が低い記録）は使わない。期間の外の記録も対象にし、推移画面では点線で値を示す
    static func personalBest(
        sessions: [TrainingSession],
        metric: Metric,
        position: PositionFilter,
        until reference: Date
    ) -> PersonalBest? {
        guard metric.hasDirection else { return nil }
        let candidates = PlayerDataEngine.eligibleSessions(sessions)
            .filter { position.matches($0) && $0.date <= reference }
            .sorted { $0.date < $1.date }
            .compactMap { s in metric.reliableValue(for: s).map { PersonalBest(sessionId: s.id, date: s.date, value: $0) } }
        return candidates.reduce(nil) { best, c in
            guard let best else { return c }
            return c.value > best.value ? c : best
        }
    }

    // MARK: - 成長サマリー（§8.4）

    static let halfComparisonMinSessions = 6
    static let halfComparisonMinPerHalf = 3

    struct HalfComparison {
        let firstAverage: Double
        let secondAverage: Double

        /// 前半比の増減（%）。前半平均が 0 なら nil
        var percentChange: Double? {
            firstAverage != 0 ? (secondAverage - firstAverage) / firstAverage * 100 : nil
        }
        /// 差分（「高さ」用、ポイント）
        var difference: Double { secondAverage - firstAverage }
    }

    /// 日付順の sessions を前半・後半に分けて平均を比べる。奇数のときは真ん中を後半に含める。
    /// 前半・後半のどちらかで値のあるセッションが3件未満なら nil
    static func halfComparison(sessionsInPeriod sessions: [TrainingSession], metric: Metric) -> HalfComparison? {
        let firstCount = sessions.count / 2
        let firstValues = sessions.prefix(firstCount).compactMap { metric.reliableValue(for: $0) }
        let secondValues = sessions.dropFirst(firstCount).compactMap { metric.reliableValue(for: $0) }
        guard firstValues.count >= halfComparisonMinPerHalf, secondValues.count >= halfComparisonMinPerHalf else { return nil }
        return HalfComparison(
            firstAverage: firstValues.reduce(0, +) / Double(firstValues.count),
            secondAverage: secondValues.reduce(0, +) / Double(secondValues.count)
        )
    }

    // MARK: - 今日の出来（§9）

    static let todayComparisonMinCount = 3

    struct TodayComparison {
        let value: Double
        let average: Double
        let comparisonCount: Int
        let rank: Int          // 今回を含めた中での順位（同じ値は同順位）
        let min: Double
        let max: Double
        let p25: Double
        let p75: Double

        var total: Int { comparisonCount + 1 }
        /// 平均比の増減（%）。平均が 0 なら nil
        var percentFromAverage: Double? { average != 0 ? (value - average) / average * 100 : nil }
        /// 平均との差（「高さ」用、ポイント）
        var differenceFromAverage: Double { value - average }
    }

    /// 今日の出来カードの比較対象。表示中のセッションより前の日時・期間内・同じポジション
    /// （表示中のセッションのポジションが未設定なら絞り込まない）
    static func comparisonSessions(
        for target: TrainingSession,
        in sessions: [TrainingSession],
        period: Period,
        calendar: Calendar = .current
    ) -> [TrainingSession] {
        let filter: PositionFilter = target.position.map { .position($0) } ?? .all
        return filteredSessions(sessions, period: period, position: filter, reference: target.date, includeReference: false, calendar: calendar)
            .filter { $0.id != target.id }
    }

    /// 今日の出来カードに出す、今回のセッションと比較対象の比較。比較対象が3件未満・今回の値がない・
    /// 今回の値が参考値（GPS 精度が低い）なら nil。比較対象の参考値も使わない
    static func todayComparison(target: TrainingSession, comparisons: [TrainingSession], metric: Metric) -> TodayComparison? {
        guard let value = metric.reliableValue(for: target) else { return nil }
        let values = comparisons.compactMap { metric.reliableValue(for: $0) }.sorted()
        guard values.count >= todayComparisonMinCount, let minV = values.first, let maxV = values.last else { return nil }
        return TodayComparison(
            value: value,
            average: values.reduce(0, +) / Double(values.count),
            comparisonCount: values.count,
            rank: values.filter { $0 > value }.count + 1,
            min: minV,
            max: maxV,
            p25: percentile(sortedValues: values, 0.25),
            p75: percentile(sortedValues: values, 0.75)
        )
    }

    /// 線形補間のパーセンタイル（sortedValues は昇順・空でないこと）
    static func percentile(sortedValues: [Double], _ p: Double) -> Double {
        guard sortedValues.count > 1 else { return sortedValues.first ?? 0 }
        let position = Double(sortedValues.count - 1) * p
        let lower = Int(position.rounded(.down))
        let upper = Swift.min(lower + 1, sortedValues.count - 1)
        let fraction = position - Double(lower)
        return sortedValues[lower] + (sortedValues[upper] - sortedValues[lower]) * fraction
    }
}
