//
//  PlayerDataEngine.swift
//  FootballGPS
//
//  「プレイヤーデータ」機能（§22）の計算ロジック。
//  新しい永続化ストアは持たず、既存の SessionDataManager.shared.sessions から
//  レベル・比較カード・バッジの状態をすべて都度計算する。

import Foundation

// MARK: - レベル・XP

enum PlayerDataEngine {
    /// 1セッションの獲得XP
    static func sessionXP(_ session: TrainingSession) -> Int {
        Int(session.totalDistance / 10) + (session.sprintCount ?? 0) * 5 + 20
    }

    static func totalXP(sessions: [TrainingSession]) -> Int {
        eligibleSessions(sessions).reduce(0) { $0 + sessionXP($1) }
    }

    static func level(forXP xp: Int) -> Int {
        xp / 1000 + 1
    }

    /// 現在のレベル内での獲得済みXP（0...999）
    static func xpIntoCurrentLevel(_ xp: Int) -> Int {
        xp % 1000
    }

    static func xpToNextLevel(_ xp: Int) -> Int {
        1000 - xpIntoCurrentLevel(xp)
    }

    // MARK: - 比較カード

    struct SessionComparison {
        let currentDistance: Double
        let recentAverageDistance: Double
        let percentDiff: Double
        let recentSessionCount: Int
    }

    /// 平均・バッジ判定の対象とするセッション（5分未満・「平均から除外」指定は対象外）。
    /// 既存の統計表示（ViewsSessionDetailView等）と同じ基準。プレイヤーデータ機能の
    /// 全計算（比較カード・レーダーチャート・バッジ）はこのフィルタを通したセッションのみを使う。
    private static func eligibleSessions(_ sessions: [TrainingSession]) -> [TrainingSession] {
        sessions.filter { $0.duration >= 300 && !$0.isExcludedFromAverage }
    }

    /// 直近セッション vs 直近5回（今回を除く）の平均距離。
    /// 直近5回が揃わない場合は nil（UI側でプレースホルダー表示する）。
    static func compareToRecentAverage(sessions: [TrainingSession]) -> SessionComparison? {
        let sorted = eligibleSessions(sessions).sorted { $0.date > $1.date }
        guard sorted.count >= 6 else { return nil }
        let current = sorted[0]
        let recent5 = Array(sorted[1...5])
        let avg = recent5.reduce(0.0) { $0 + $1.totalDistance } / Double(recent5.count)
        guard avg > 0 else { return nil }
        let diff = (current.totalDistance - avg) / avg * 100
        return SessionComparison(
            currentDistance: current.totalDistance,
            recentAverageDistance: avg,
            percentDiff: diff,
            recentSessionCount: recent5.count
        )
    }

    // MARK: - バッジ共通の型

    enum BadgeTier: Int, Comparable {
        case start, bronze, silver, gold, platinum

        static func < (lhs: BadgeTier, rhs: BadgeTier) -> Bool { lhs.rawValue < rhs.rawValue }

        var displayName: String {
            switch self {
            case .start:    return "スタート"
            case .bronze:   return "ブロンズ"
            case .silver:   return "シルバー"
            case .gold:     return "ゴールド"
            case .platinum: return "プラチナ"
            }
        }
    }

    struct BadgeProgress: Identifiable {
        let id: String
        let name: String
        let sfSymbol: String
        let tier: BadgeTier?
        let unlocked: Bool
        let currentValue: Int
        let nextThreshold: Int?
        let unavailableReason: String?
        /// サプライズ系で未解除の場合、UI側で名前・アイコンを「？」表示にする
        let isHidden: Bool

        init(
            id: String,
            name: String,
            sfSymbol: String,
            tier: BadgeTier? = nil,
            unlocked: Bool,
            currentValue: Int = 0,
            nextThreshold: Int? = nil,
            unavailableReason: String? = nil,
            isHidden: Bool = false
        ) {
            self.id = id
            self.name = name
            self.sfSymbol = sfSymbol
            self.tier = tier
            self.unlocked = unlocked
            self.currentValue = currentValue
            self.nextThreshold = nextThreshold
            self.unavailableReason = unavailableReason
            self.isHidden = isHidden
        }
    }

    struct BadgeSection: Identifiable {
        let id: String
        let title: String
        let badges: [BadgeProgress]
    }

    private static let standardTiers: [BadgeTier] = [.bronze, .silver, .gold, .platinum]
    private static let sessionCountTiers: [BadgeTier] = [.start, .bronze, .silver, .gold, .platinum]

    /// thresholds/tiers は同じ長さで、段階が低い順に並んでいること
    private static func tierForCount(
        _ value: Int,
        thresholds: [Int],
        tiers: [BadgeTier]
    ) -> (tier: BadgeTier?, next: Int?) {
        var achieved: BadgeTier?
        for (index, threshold) in thresholds.enumerated() {
            if value >= threshold {
                achieved = tiers[index]
            } else {
                return (achieved, threshold)
            }
        }
        return (achieved, nil)
    }

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

    private static func overallScore(for session: TrainingSession) -> Double {
        radar(for: session).overallScore
    }

    private static func radarValues(for session: TrainingSession) -> [Double] {
        let r = radar(for: session)
        return [r.distance, r.sprint, r.agility, r.stamina, r.intensity, r.topSpeed]
    }

    // MARK: - レーダーチャート: 直近5回平均 vs 自己ベスト

    static let radarAxisLabels = ["走力", "スプリント", "アジリティ", "スタミナ", "高強度", "最高速度"]

    struct RadarComparison {
        let recentAverage: [Double] // 直近5回（無ければあるだけ）の各軸平均
        let personalBest: [Double]  // 全セッション中の各軸最高値（軸ごとに別セッションで良い）
        let latestSession: [Double] // 直前（最新）1回のセッション
    }

    static func radarComparison(sessions: [TrainingSession]) -> RadarComparison? {
        let eligible = eligibleSessions(sessions)
        guard !eligible.isEmpty else { return nil }
        let sortedByRecent = eligible.sorted { $0.date > $1.date }
        let recent = Array(sortedByRecent.prefix(5))

        let allValues = eligible.map { radarValues(for: $0) }
        let recentValues = recent.map { radarValues(for: $0) }
        let latestValues = radarValues(for: sortedByRecent[0])

        func average(_ arrays: [[Double]]) -> [Double] {
            var sums = [Double](repeating: 0, count: 6)
            for arr in arrays {
                for i in 0..<6 { sums[i] += arr[i] }
            }
            return sums.map { $0 / Double(arrays.count) }
        }
        func maxPerAxis(_ arrays: [[Double]]) -> [Double] {
            var best = [Double](repeating: 0, count: 6)
            for arr in arrays {
                for i in 0..<6 { best[i] = max(best[i], arr[i]) }
            }
            return best
        }

        return RadarComparison(
            recentAverage: average(recentValues),
            personalBest: maxPerAxis(allValues),
            latestSession: latestValues
        )
    }

    // MARK: - A. 累計マイルストーン（選手カテゴリにより閾値が異なる）

    private static let distanceThresholds: [PlayerCategory: [Int]] = [
        .youth:   [10_000, 50_000, 100_000, 500_000],
        .general: [10_000, 50_000, 150_000, 250_000],
    ]
    private static let sessionCountThresholds: [PlayerCategory: [Int]] = [
        .youth:   [1, 5, 20, 50, 150],
        .general: [1, 5, 20, 35, 50],
    ]
    private static let sprintThresholds: [PlayerCategory: [Int]] = [
        .youth:   [50, 200, 500, 1500],
        .general: [50, 200, 400, 600],
    ]

    private static let categoryUnavailableReason = "選手カテゴリを設定すると挑戦できます"

    static func milestoneBadges(sessions: [TrainingSession], playerCategory: PlayerCategory?) -> [BadgeProgress] {
        guard let category = playerCategory else {
            return [
                BadgeProgress(id: "milestone-distance", name: "累計距離", sfSymbol: "shoeprints.fill", unlocked: false, unavailableReason: categoryUnavailableReason),
                BadgeProgress(id: "milestone-sessions", name: "累計セッション数", sfSymbol: "calendar.badge.checkmark", unlocked: false, unavailableReason: categoryUnavailableReason),
                BadgeProgress(id: "milestone-sprints", name: "累計スプリント", sfSymbol: "figure.run.square.stack", unlocked: false, unavailableReason: categoryUnavailableReason),
            ]
        }

        let totalDistance = Int(sessions.reduce(0.0) { $0 + $1.totalDistance })
        let totalSessions = sessions.count
        let totalSprints = sessions.reduce(0) { $0 + ($1.sprintCount ?? 0) }

        let (distanceTier, distanceNext) = tierForCount(totalDistance, thresholds: distanceThresholds[category]!, tiers: standardTiers)
        let (sessionTier, sessionNext) = tierForCount(totalSessions, thresholds: sessionCountThresholds[category]!, tiers: sessionCountTiers)
        let (sprintTier, sprintNext) = tierForCount(totalSprints, thresholds: sprintThresholds[category]!, tiers: standardTiers)

        return [
            BadgeProgress(id: "milestone-distance", name: "累計距離", sfSymbol: "shoeprints.fill", tier: distanceTier, unlocked: distanceTier != nil, currentValue: totalDistance, nextThreshold: distanceNext),
            BadgeProgress(id: "milestone-sessions", name: "累計セッション数", sfSymbol: "calendar.badge.checkmark", tier: sessionTier, unlocked: sessionTier != nil, currentValue: totalSessions, nextThreshold: sessionNext),
            BadgeProgress(id: "milestone-sprints", name: "累計スプリント", sfSymbol: "figure.run.square.stack", tier: sprintTier, unlocked: sprintTier != nil, currentValue: totalSprints, nextThreshold: sprintNext),
        ]
    }

    // MARK: - B. 好セッション達成回数（選手カテゴリにより閾値が異なる）

    private static let goodSessionThresholds: [PlayerCategory: [Int]] = [
        .youth:   [1, 5, 15, 30],
        .general: [1, 5, 10, 15],
    ]

    static func goodSessionBadges(sessions: [TrainingSession], playerCategory: PlayerCategory?) -> [BadgeProgress] {
        guard let category = playerCategory else {
            return [
                BadgeProgress(id: "good-longrunner", name: "ロングランナー", sfSymbol: "figure.walk", unlocked: false, unavailableReason: categoryUnavailableReason),
                BadgeProgress(id: "good-sprinter", name: "スプリンター", sfSymbol: "figure.run", unlocked: false, unavailableReason: categoryUnavailableReason),
                BadgeProgress(id: "good-elite", name: "エリート", sfSymbol: "trophy.fill", unlocked: false, unavailableReason: categoryUnavailableReason),
            ]
        }

        let longRunCount = sessions.filter { $0.totalDistance >= 5000 }.count
        let sprinterCount = sessions.filter { ($0.sprintCount ?? 0) >= 20 }.count
        let eliteCount = sessions.filter { overallScore(for: $0) >= 80 }.count

        let thresholds = goodSessionThresholds[category]!
        let (longRunTier, longRunNext) = tierForCount(longRunCount, thresholds: thresholds, tiers: standardTiers)
        let (sprinterTier, sprinterNext) = tierForCount(sprinterCount, thresholds: thresholds, tiers: standardTiers)
        let (eliteTier, eliteNext) = tierForCount(eliteCount, thresholds: thresholds, tiers: standardTiers)

        return [
            BadgeProgress(id: "good-longrunner", name: "ロングランナー", sfSymbol: "figure.walk", tier: longRunTier, unlocked: longRunTier != nil, currentValue: longRunCount, nextThreshold: longRunNext),
            BadgeProgress(id: "good-sprinter", name: "スプリンター", sfSymbol: "figure.run", tier: sprinterTier, unlocked: sprinterTier != nil, currentValue: sprinterCount, nextThreshold: sprinterNext),
            BadgeProgress(id: "good-elite", name: "エリート", sfSymbol: "trophy.fill", tier: eliteTier, unlocked: eliteTier != nil, currentValue: eliteCount, nextThreshold: eliteNext),
        ]
    }

    // MARK: - C. 継続（週単位。一度達成したら永久に解除状態を維持する）

    private struct WeekAnchor {
        static let referenceMonday: Date = {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone.current
            var comps = DateComponents()
            comps.year = 2000
            comps.month = 1
            comps.day = 3 // 2000-01-03 は月曜日
            return calendar.date(from: comps) ?? Date(timeIntervalSince1970: 0)
        }()
    }

    private static func weekIndex(for date: Date) -> Int {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let startOfDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: WeekAnchor.referenceMonday, to: startOfDay).day ?? 0
        return Int((Double(days) / 7).rounded(.down))
    }

    private static func longestConsecutiveRun(_ indices: Set<Int>) -> Int {
        let sorted = indices.sorted()
        guard !sorted.isEmpty else { return 0 }
        var longest = 1
        var current = 1
        for i in 1..<sorted.count {
            if sorted[i] == sorted[i - 1] + 1 {
                current += 1
                longest = max(longest, current)
            } else {
                current = 1
            }
        }
        return longest
    }

    private static func currentConsecutiveRun(_ indices: Set<Int>) -> Int {
        guard let latest = indices.max() else { return 0 }
        var count = 0
        var i = latest
        while indices.contains(i) {
            count += 1
            i -= 1
        }
        return count
    }

    static func streakBadges(sessions: [TrainingSession]) -> [BadgeProgress] {
        let weekIndices = Set(sessions.map { weekIndex(for: $0.date) })
        let longestStreak = longestConsecutiveRun(weekIndices)
        let currentStreak = currentConsecutiveRun(weekIndices)

        let defs: [(id: String, name: String, symbol: String, weeks: Int)] = [
            ("streak-3", "継続の芽生え", "leaf.fill", 3),
            ("streak-8", "継続は力なり", "flame", 8),
            ("streak-26", "揺るがぬ情熱", "flame.fill", 26),
            ("streak-52", "鉄人", "figure.strengthtraining.traditional", 52),
        ]
        return defs.map { def in
            BadgeProgress(
                id: def.id,
                name: def.name,
                sfSymbol: def.symbol,
                unlocked: longestStreak >= def.weeks,
                currentValue: currentStreak,
                nextThreshold: longestStreak >= def.weeks ? nil : def.weeks
            )
        }
    }

    // MARK: - D. 月替わりチャレンジ（相対評価）

    private struct MonthKey: Hashable, Comparable {
        let year: Int
        let month: Int
        static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
            (lhs.year, lhs.month) < (rhs.year, rhs.month)
        }
        var displayName: String { "\(year)年\(month)月" }
    }

    static func monthlyChallengeBadges(sessions: [TrainingSession]) -> [BadgeProgress] {
        var totals: [MonthKey: Double] = [:]
        for session in sessions {
            let comps = Calendar.current.dateComponents([.year, .month], from: session.date)
            guard let y = comps.year, let m = comps.month else { continue }
            totals[MonthKey(year: y, month: m), default: 0] += session.totalDistance
        }

        let sortedMonths = totals.keys.sorted()
        var results: [BadgeProgress] = []
        for (index, key) in sortedMonths.enumerated() {
            let priorMonths = sortedMonths[max(0, index - 3)..<index]
            guard !priorMonths.isEmpty else { continue }
            let priorAverage = priorMonths.reduce(0.0) { $0 + (totals[$1] ?? 0) } / Double(priorMonths.count)
            guard priorAverage > 0, let thisTotal = totals[key], thisTotal > priorAverage else { continue }
            results.append(BadgeProgress(
                id: "monthly-\(key.year)-\(key.month)",
                name: "\(key.displayName)\nチャレンジャー",
                sfSymbol: "calendar.badge.clock",
                unlocked: true,
                currentValue: Int(thisTotal)
            ))
        }
        return results.reversed() // 新しい月を先頭に
    }

    // MARK: - E. 利用継続の記念バッジ

    static func anniversaryBadges(sessions: [TrainingSession]) -> [BadgeProgress] {
        guard let start = sessions.map(\.date).min() else { return [] }
        let daysSinceStart = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0

        let defs: [(id: String, name: String, days: Int)] = [
            ("anniv-1m", "利用開始1ヶ月", 30),
            ("anniv-6m", "利用開始半年", 180),
            ("anniv-1y", "利用開始1年", 365),
        ]
        return defs.map { def in
            BadgeProgress(
                id: def.id,
                name: def.name,
                sfSymbol: "gift.fill",
                unlocked: daysSinceStart >= def.days,
                currentValue: daysSinceStart,
                nextThreshold: daysSinceStart >= def.days ? nil : def.days
            )
        }
    }

    // MARK: - F. サプライズ系・隠しバッジ

    static func surpriseBadges(sessions: [TrainingSession]) -> [BadgeProgress] {
        let earlyBird = sessions.contains { Calendar.current.component(.hour, from: $0.date) < 6 }
        let nightOwl = sessions.contains { Calendar.current.component(.hour, from: $0.date) >= 21 }
        let awakened = hasThreeConsecutivePersonalBests(sessions: sessions)

        return [
            BadgeProgress(id: "surprise-earlybird", name: "早朝の一番乗り", sfSymbol: "sunrise.fill", unlocked: earlyBird, isHidden: !earlyBird),
            BadgeProgress(id: "surprise-nightowl", name: "夜更けの情熱", sfSymbol: "moon.stars.fill", unlocked: nightOwl, isHidden: !nightOwl),
            BadgeProgress(id: "surprise-awakened", name: "覚醒", sfSymbol: "sparkles", unlocked: awakened, isHidden: !awakened),
        ]
    }

    /// 日付順に3セッション連続で、それぞれが「それまでの全セッション中の最高スコア」を更新したか
    private static func hasThreeConsecutivePersonalBests(sessions: [TrainingSession]) -> Bool {
        let sorted = sessions.sorted { $0.date < $1.date }
        guard sorted.count >= 3 else { return false }
        var bestSoFar = -Double.infinity
        var streak = 0
        for session in sorted {
            let score = overallScore(for: session)
            if score > bestSoFar {
                bestSoFar = score
                streak += 1
                if streak >= 3 { return true }
            } else {
                streak = 0
            }
        }
        return false
    }

    // MARK: - まとめ

    static func allSections(sessions: [TrainingSession], playerCategory: PlayerCategory?) -> [BadgeSection] {
        let eligible = eligibleSessions(sessions)
        return [
            BadgeSection(id: "milestones", title: "累計マイルストーン", badges: milestoneBadges(sessions: eligible, playerCategory: playerCategory)),
            BadgeSection(id: "good-sessions", title: "好セッション達成", badges: goodSessionBadges(sessions: eligible, playerCategory: playerCategory)),
            BadgeSection(id: "streaks", title: "継続", badges: streakBadges(sessions: eligible)),
            BadgeSection(id: "monthly", title: "月替わりチャレンジ", badges: monthlyChallengeBadges(sessions: eligible)),
            BadgeSection(id: "memorial-surprise", title: "記念・サプライズ", badges: anniversaryBadges(sessions: eligible) + surpriseBadges(sessions: eligible)),
        ]
    }
}
