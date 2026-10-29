//
//  MonthlyRecapEngine.swift
//  FootballGPS
//
//  月ごとのまとめの集計（技術実装仕様書 §27.2・§27.3）。表示は MonthlyRecapStoryView
//

import Foundation
import CoreGraphics

/// まとめの対象の月
struct RecapMonth: Hashable, Comparable, Identifiable {
    let year: Int
    let month: Int

    var id: String { String(format: "%04d-%02d", year, month) }
    var title: String { "\(month)月" }
    var fullTitle: String { "\(year)年\(month)月" }

    static func < (lhs: RecapMonth, rhs: RecapMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 0, month: components.month ?? 1)
    }

    func start(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    func end(calendar: Calendar = .current) -> Date {
        next.start(calendar: calendar)
    }

    var previous: RecapMonth {
        month == 1 ? RecapMonth(year: year - 1, month: 12) : RecapMonth(year: year, month: month - 1)
    }

    var next: RecapMonth {
        month == 12 ? RecapMonth(year: year + 1, month: 1) : RecapMonth(year: year, month: month + 1)
    }
}

/// 先月と比べた1つの指標
struct RecapMetricChange {
    enum Direction { case up, kept, down }

    let previous: Double
    let current: Double

    var direction: Direction {
        guard previous > 0 else { return .kept }
        let ratio = current / previous
        if ratio > 1 + MonthlyRecapEngine.keptTolerance { return .up }
        if ratio < 1 - MonthlyRecapEngine.keptTolerance { return .down }
        return .kept
    }
}

struct MonthlyRecap {
    let month: RecapMonth
    /// 対象のセッション（日付の古い順）
    let sessions: [TrainingSession]
    let totalDuration: TimeInterval
    let totalDistance: Double
    let totalSprints: Int
    /// GPSの精度が低い記録を除いた最高速度（m/s）。すべて精度が低ければ nil
    let bestMaxSpeed: Double?
    /// プレイヤータイプの総合スコアが最も高いセッション
    let bestSession: TrainingSession
    let bestSessionScore: Int
    /// 先月と比べた値。先月に対象のセッションがなければ nil
    let distancePerMinute: RecapMetricChange?
    let maxSpeed: RecapMetricChange?
    let sprintsPerSession: RecapMetricChange?
    let topPlayerType: PlayerType
    let topPosition: PlayingPosition?
    /// その月に新しく獲得・段階が上がったバッジ
    let newBadges: [PlayerDataEngine.BadgeProgress]
    /// その月にプレーした日（日にち）。活動カレンダー用（§27.7 E）
    let playedDays: Set<Int>
    /// その月の最後にプレーした週まで、何週続けてプレーしたか（前の月からの続きも数える）
    let weeklyStreak: Int
    /// その月に更新した自己ベスト。前の月までに記録がなければ空（§27.7 F）
    let personalBests: [RecapPersonalBest]

    var sessionCount: Int { sessions.count }

    /// よくプレーした時間帯。最も多い時間帯（同数なら朝→日中→夕方→夜の順）と、その中で最も多い開始時刻
    var timeOfDay: RecapTimeOfDay? {
        guard !sessions.isEmpty else { return nil }
        var counts = Array(repeating: 0, count: 24)
        for session in sessions { counts[Calendar.current.component(.hour, from: session.date)] += 1 }
        let bandCounts = RecapTimeBand.allCases.map { band in
            (band, counts.indices.filter { RecapTimeBand.band(forHour: $0) == band }.map { counts[$0] }.reduce(0, +))
        }
        guard let band = bandCounts.max(by: { $0.1 < $1.1 })?.0 else { return nil }
        let peak = counts.indices
            .filter { RecapTimeBand.band(forHour: $0) == band }
            .max { counts[$0] < counts[$1] } ?? 0
        return RecapTimeOfDay(band: band, peakHour: peak, hourCounts: counts)
    }

    /// クイズ「一番走った日はどれ？」。走った日が3日未満なら作らない。
    /// 選択肢は1位・2位・一番少なかった日で、並びは月ごとに変える（毎回同じ月なら同じ並び）
    var quiz: RecapQuiz? {
        let days = dailyDistances
        guard days.count >= 3 else { return nil }
        let picks = [days[0], days[1], days[days.count - 1]]
        let shift = month.month % 3
        let ordered = Array(picks[shift...] + picks[..<shift])
        return RecapQuiz(options: ordered, correctIndex: (3 - shift) % 3)
    }

    /// 日ごとの走行距離（同じ日に複数のセッションがあれば合計する）。距離の多い順、0mの日は除く（§27.3 画面2）
    var dailyDistances: [(day: Date, distance: Double)] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        return grouped
            .map { (day: $0.key, distance: $0.value.map(\.totalDistance).reduce(0, +)) }
            .filter { $0.distance > 0 }
            .sorted { $0.distance == $1.distance ? $0.day < $1.day : $0.distance > $1.distance }
    }
    var hasComparison: Bool { distancePerMinute != nil }
}

/// その月で一番速かったスプリントの再生用データ（§27.7 A）
struct SprintReplay {
    let date: Date
    /// スプリント区間の最高速度（m/s）
    let maxSpeed: Double
    /// スプリント区間の距離（m）
    let distance: Double
    /// スプリント区間の長さ（秒）
    let duration: TimeInterval
    /// 前後の助走を含めた軌跡（フィールド内の割合の位置、HeatmapGrid.normalizedPoints と同じ座標）
    let path: [CGPoint]
    /// 各点の速度（m/s）
    let speeds: [Double]
    /// 軌跡のうちスプリント区間が始まる・終わる点の番号
    let sprintStart: Int
    let sprintEnd: Int
}

/// よくプレーした時間帯（§27.9）。セッションの開始時刻で分ける
enum RecapTimeBand: CaseIterable {
    case morning, daytime, evening, night

    static func band(forHour hour: Int) -> RecapTimeBand {
        switch hour {
        case 4..<10:  return .morning
        case 10..<15: return .daytime
        case 15..<18: return .evening
        default:      return .night
        }
    }

    var persona: String {
        switch self {
        case .morning: return "朝練派"
        case .daytime: return "日中派"
        case .evening: return "夕方派"
        case .night:   return "ナイター派"
        }
    }

    /// 語りかけの一言
    var line: String {
        switch self {
        case .morning: return "朝日とともに走る、朝練派。"
        case .daytime: return "太陽の下で走る、日中派。"
        case .evening: return "夕焼けのピッチを駆ける、夕方派。"
        case .night:   return "照明の下で輝く、ナイター派。"
        }
    }
}

struct RecapTimeOfDay {
    let band: RecapTimeBand
    /// その時間帯の中で最も多かった開始時刻（時）
    let peakHour: Int
    /// 0〜23時の開始回数
    let hourCounts: [Int]
}

/// 自己ベストの更新（§27.7 F）
struct RecapPersonalBest: Equatable {
    let title: String
    /// 単位つきで表示する値
    let value: String
    let previous: String
}

/// クイズ「一番走った日はどれ？」（§27.7 C）
struct RecapQuiz {
    let options: [(day: Date, distance: Double)]
    let correctIndex: Int
}

/// 日ごとに積み上がるヒートマップの1コマ（§27.7 B）
struct HeatmapFrame {
    let day: Date
    let grid: [[Double]]
}

enum MonthlyRecapEngine {
    /// まとめを作る最低の回数（Strava と同じ考え方。少ないと内容が薄くなる）
    static let minimumSessions = 3
    /// 先月との差がこの割合以内なら「維持」
    static let keptTolerance = 0.05

    /// 対象のセッション（月の範囲内で、プレイヤーデータと同じ条件を満たすもの）
    static func eligibleSessions(in month: RecapMonth, from sessions: [TrainingSession]) -> [TrainingSession] {
        let start = month.start()
        let end = month.end()
        return PlayerDataEngine.eligibleSessions(sessions)
            .filter { $0.date >= start && $0.date < end }
            .sorted { $0.date < $1.date }
    }

    /// まとめを見られる月（終わった月で、対象のセッションが minimumSessions 回以上）。新しい順
    static func availableMonths(sessions: [TrainingSession], now: Date = Date()) -> [RecapMonth] {
        let current = RecapMonth(date: now)
        let months = Set(PlayerDataEngine.eligibleSessions(sessions).map { RecapMonth(date: $0.date) })
        return months
            .filter { $0 < current && eligibleSessions(in: $0, from: sessions).count >= minimumSessions }
            .sorted(by: >)
    }

    static func recap(
        for month: RecapMonth,
        sessions allSessions: [TrainingSession],
        playerCategory: PlayerCategory?
    ) -> MonthlyRecap? {
        let sessions = eligibleSessions(in: month, from: allSessions)
        guard sessions.count >= minimumSessions else { return nil }

        let scored = sessions.map { ($0, radar(for: $0)) }
        guard let best = scored.max(by: { $0.1.overallScore < $1.1.overallScore }) else { return nil }

        let previousSessions = eligibleSessions(in: month.previous, from: allSessions)
        let current = averages(sessions)
        let previous = previousSessions.isEmpty ? nil : averages(previousSessions)

        return MonthlyRecap(
            month: month,
            sessions: sessions,
            totalDuration: sessions.map(\.duration).reduce(0, +),
            totalDistance: sessions.map(\.totalDistance).reduce(0, +),
            totalSprints: sessions.map { $0.sprintCount ?? 0 }.reduce(0, +),
            bestMaxSpeed: bestMaxSpeed(sessions),
            bestSession: best.0,
            bestSessionScore: Int(best.1.overallScore),
            distancePerMinute: previous.map { RecapMetricChange(previous: $0.distancePerMinute, current: current.distancePerMinute) },
            maxSpeed: previous.flatMap { prev in
                guard let p = prev.maxSpeed, let c = current.maxSpeed else { return nil }
                return RecapMetricChange(previous: p, current: c)
            },
            sprintsPerSession: previous.map { RecapMetricChange(previous: $0.sprintsPerSession, current: current.sprintsPerSession) },
            topPlayerType: mostFrequent(scored.map(\.1.playerType)) ?? best.1.playerType,
            topPosition: mostFrequent(sessions.compactMap(\.position)),
            newBadges: newBadges(in: month, sessions: allSessions, playerCategory: playerCategory),
            playedDays: Set(sessions.map { Calendar.current.component(.day, from: $0.date) }),
            weeklyStreak: weeklyStreak(endingIn: month, sessions: allSessions),
            personalBests: personalBests(in: month, sessions: allSessions)
        )
    }

    // MARK: - 集計の部品

    private static func radar(for session: TrainingSession) -> PlayerRadarData {
        SessionDataManager.computePlayerRadar(
            totalDistance: session.totalDistance,
            duration: session.duration,
            sprintCount: session.sprintCount ?? 0,
            agilityTurnCount: session.agilityTurnCount,
            staminaDrop: session.staminaDrop,
            hrIntensityRatio: session.hrIntensityRatio,
            maxSpeed: session.maxSpeed
        )
    }

    private static func bestMaxSpeed(_ sessions: [TrainingSession]) -> Double? {
        sessions.filter { !$0.isLowGPSAccuracy }.map(\.maxSpeed).max()
    }

    private static func averages(_ sessions: [TrainingSession]) -> (distancePerMinute: Double, maxSpeed: Double?, sprintsPerSession: Double) {
        let minutes = sessions.map(\.duration).reduce(0, +) / 60
        let distance = sessions.map(\.totalDistance).reduce(0, +)
        let sprints = Double(sessions.map { $0.sprintCount ?? 0 }.reduce(0, +))
        return (
            distancePerMinute: minutes > 0 ? distance / minutes : 0,
            maxSpeed: bestMaxSpeed(sessions),
            sprintsPerSession: sprints / Double(max(sessions.count, 1))
        )
    }

    /// 最も多い値。同数なら先に出てきたもの
    private static func mostFrequent<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return values.max { counts[$0, default: 0] < counts[$1, default: 0] }
    }

    /// 月末時点と前月末時点のバッジを比べ、新しく獲得したもの・段階が上がったものを返す
    static func newBadges(
        in month: RecapMonth,
        sessions: [TrainingSession],
        playerCategory: PlayerCategory?
    ) -> [PlayerDataEngine.BadgeProgress] {
        func badges(until date: Date) -> [String: PlayerDataEngine.BadgeProgress] {
            let sections = PlayerDataEngine.allSections(
                sessions: sessions.filter { $0.date < date },
                playerCategory: playerCategory
            )
            return Dictionary(sections.flatMap(\.badges).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
        let before = badges(until: month.start())
        let after = badges(until: month.end())
        return after.values
            .filter { badge in
                guard badge.unlocked else { return false }
                guard let old = before[badge.id], old.unlocked else { return true }
                if let newTier = badge.tier, let oldTier = old.tier { return newTier > oldTier }
                return false
            }
            .sorted { $0.name < $1.name }
    }

    // MARK: - 継続と自己ベスト（§27.7 E・F）

    /// その月の最後にプレーした週から、さかのぼって何週続けてプレーしたか。その月にプレーした週がなければ 0
    static func weeklyStreak(endingIn month: RecapMonth, sessions: [TrainingSession]) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2  // 月曜始まり
        func weekStart(_ date: Date) -> Date {
            calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        }
        let end = month.end()
        let played = Set(PlayerDataEngine.eligibleSessions(sessions).filter { $0.date < end }.map { weekStart($0.date) })
        guard let last = eligibleSessions(in: month, from: sessions).last.map({ weekStart($0.date) }) else { return 0 }
        var count = 0
        var week = last
        while played.contains(week) {
            count += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return count
    }

    /// その月に更新した自己ベスト（1回の走行距離、最高速度、1回のスプリント回数）。
    /// 前の月までに記録がない（初めての月）なら、すべてが自己ベストになってしまうので空にする
    static func personalBests(in month: RecapMonth, sessions: [TrainingSession]) -> [RecapPersonalBest] {
        let before = PlayerDataEngine.eligibleSessions(sessions).filter { $0.date < month.start() }
        let current = eligibleSessions(in: month, from: sessions)
        guard !before.isEmpty, !current.isEmpty else { return [] }

        var results: [RecapPersonalBest] = []
        func check(_ title: String, _ value: (TrainingSession) -> Double?, format: (Double) -> String) {
            guard let now = current.compactMap(value).max(),
                  let old = before.compactMap(value).max(), now > old else { return }
            results.append(RecapPersonalBest(title: title, value: format(now), previous: format(old)))
        }
        check("1回の走行距離", { $0.totalDistance }, format: { String(format: "%.2f km", $0 / 1000) })
        check("最高速度", { $0.isLowGPSAccuracy ? nil : $0.maxSpeed }, format: { String(format: "%.1f km/h", $0 * 3.6) })
        check("1回のスプリント", { $0.sprintCount.map(Double.init) }, format: { "\(Int($0)) 回" })
        return results
    }

    // MARK: - 二つ名（AIの二つ名がない月はルールで作る）

    /// AIの二つ名の中から、その月のまとめに使う1つを選ぶ。
    /// 一番よかったセッションに対して作ったものを優先し、なければその月のセッションの二つ名で一番新しいもの。
    /// その月のセッション以外に対して作ったものは使わない（作った日時ではなくセッションで判定する）
    static func pickNickname(_ rows: [NicknameRow], recap: MonthlyRecap) -> String? {
        let sessionIds = Set(recap.sessions.map(\.id))
        let inMonth = rows
            .filter { $0.localSessionId.map(sessionIds.contains) ?? false }
            .sorted { $0.createdAt > $1.createdAt }
        return (inMonth.first { $0.localSessionId == recap.bestSession.id } ?? inMonth.first)?.nickname
    }

    /// ポジションとプレイヤータイプを組み合わせた二つ名（例: 「中盤のスピードスター」）。
    /// AI機能は公開時に隠すため、AIの二つ名がない利用者にもこの二つ名を出す（§27.3）
    static func ruleNickname(position: PlayingPosition?, playerType: PlayerType) -> String {
        let place: String
        switch position {
        case .fw:  place = "最前線の"
        case .wg:  place = "サイドの"
        case .mf:  place = "中盤の"
        case .cb:  place = "最終ラインの"
        case .sb:  place = "後方サイドの"
        case .wb:  place = "両翼の"
        case .gk:  place = "ゴール前の"
        case nil:  place = "ピッチの"
        }
        let role: String
        switch playerType {
        case .longRunner: role = "ロングランナー"
        case .sprinter:   role = "スプリンター"
        case .agile:      role = "キレ者"
        case .stamina:    role = "鉄人"
        case .hardWorker: role = "ハードワーカー"
        case .speedster:  role = "スピードスター"
        }
        return place + role
    }

    // MARK: - 重ねたヒートマップ

    /// その月のセッションを重ねたヒートマップの格子。フィールドの登録がないセッションは除く。
    /// 1つも重ねられなければ nil
    @MainActor
    static func combinedHeatmap(_ sessions: [TrainingSession], rows: Int, cols: Int) -> [[Double]]? {
        let points: [CGPoint] = sessions.flatMap { session -> [CGPoint] in
            guard let fieldId = session.fieldId,
                  let field = FieldManager.shared.getField(by: fieldId),
                  let gpsData = SessionDataManager.shared.getGPSData(for: session.id) else { return [] }
            return HeatmapGrid.normalizedPoints(gpsData.points, field: field, isFlipped: session.isFlipped)
        }
        guard !points.isEmpty else { return nil }
        return HeatmapGrid.compute(normalizedPoints: points, rows: rows, cols: cols)
    }

    /// 日ごとに積み上げたヒートマップ。各コマはその日までのセッションを重ねたもので、
    /// 最後のコマ（全部重ねたもの）の最大値で正規化し、色づいていく様子を同じ尺度で見せる。重ねられなければ nil
    @MainActor
    static func heatmapFrames(_ sessions: [TrainingSession], rows: Int, cols: Int) -> [HeatmapFrame]? {
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.date) }
        var accumulated = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        var rawFrames: [(day: Date, grid: [[Double]])] = []
        for day in byDay.keys.sorted() {
            let points: [CGPoint] = (byDay[day] ?? []).flatMap { session -> [CGPoint] in
                guard let fieldId = session.fieldId,
                      let field = FieldManager.shared.getField(by: fieldId),
                      let gpsData = SessionDataManager.shared.getGPSData(for: session.id) else { return [] }
                return HeatmapGrid.normalizedPoints(gpsData.points, field: field, isFlipped: session.isFlipped)
            }
            guard !points.isEmpty else { continue }
            let raw = HeatmapGrid.rawGrid(normalizedPoints: points, rows: rows, cols: cols)
            for r in 0..<rows { for c in 0..<cols { accumulated[r][c] += raw[r][c] } }
            rawFrames.append((day, accumulated))
        }
        guard let last = rawFrames.last else { return nil }
        let maxValue = last.grid.flatMap { $0 }.max() ?? 0
        return rawFrames.map { HeatmapFrame(day: $0.day, grid: HeatmapGrid.normalized($0.grid, maxValue: maxValue)) }
    }

    /// その月で一番速かったスプリント。GPSの精度が低い記録とフィールドの登録がないセッションは除く。
    /// 前後に助走として数点ずつ加える。見つからなければ nil
    @MainActor
    static func fastestSprint(_ sessions: [TrainingSession]) -> SprintReplay? {
        let leadIn = 4
        var best: SprintReplay?
        for session in sessions where !session.isLowGPSAccuracy {
            guard let fieldId = session.fieldId,
                  let field = FieldManager.shared.getField(by: fieldId),
                  let gpsData = SessionDataManager.shared.getGPSData(for: session.id) else { continue }
            // スプリントの検出と同じく、外れ値を除いた速度を使う
            let points = SessionDataManager.removingSpeedSpikes(gpsData.points)
            for segment in SessionDataManager.computeSprintSegments(gpsData.points)
            where segment.maxSpeed > (best?.maxSpeed ?? 0) {
                let from = max(0, segment.startIndex - leadIn)
                let to = min(points.count - 1, segment.endIndex + leadIn)
                let slice = Array(points[from...to])
                let path = HeatmapGrid.normalizedPoints(slice, field: field, isFlipped: session.isFlipped)
                // フィールドの外の点が除かれて数がずれた場合は、再生できないので使わない
                guard path.count == slice.count, path.count >= 2 else { continue }
                best = SprintReplay(
                    date: points[segment.startIndex].timestamp,
                    maxSpeed: segment.maxSpeed,
                    distance: segment.distance,
                    duration: points[segment.endIndex].timestamp.timeIntervalSince(points[segment.startIndex].timestamp),
                    path: path,
                    speeds: slice.map(\.speed),
                    sprintStart: segment.startIndex - from,
                    sprintEnd: segment.endIndex - from
                )
            }
        }
        return best
    }

    /// 1セッションのヒートマップの格子（一番よかったセッションの画面用）
    @MainActor
    static func sessionHeatmap(_ session: TrainingSession, rows: Int, cols: Int) -> [[Double]]? {
        combinedHeatmap([session], rows: rows, cols: cols)
    }
}
