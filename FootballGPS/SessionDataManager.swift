//
//  SessionDataManager.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import Foundation
import Combine
import CoreLocation

/// セッションデータを管理するクラス（iPhone側）
@MainActor
class SessionDataManager: ObservableObject {

    static let shared = SessionDataManager()

    @Published var sessions: [TrainingSession] = []
    private var gpsDataCache: [String: GPSData] = [:]  // sessionId -> GPSData（LRU、最大3件）
    @Published var isMigrating: Bool = false

    private let sessionsKey = "savedSessions"
    private let gpsDataPrefix = "gpsData_"                  // 旧 UserDefaults キー（移行時のみ使用）
    private let migrationKey = "gpsDataMigrationCompleted"
    private let iCloudBackupEnabledKey = "gpsDataiCloudBackupEnabled"

    // LRU キャッシュ管理（最大3件）
    private var lruOrder: [String] = []
    private let maxCacheSize = 3

    private init() {
        loadSessions()
        print("📱 SessionDataManager初期化完了: \(sessions.count)件のセッション")

        // GPS / アジリティ ディレクトリを確保してマイグレーション実行
        ensureGPSDirectoryExists()
        ensureAgilityDirectoryExists()
        migrateGPSDataIfNeeded()

        // シミュレーター用: Watch側から保存されたデータを読み込む
        #if targetEnvironment(simulator)
        loadPendingSessionsFromWatch()
        #endif
    }

    // MARK: - Save/Load Sessions

    /// セッションを保存（sprintCount は GPS データから再計算して上書きする）
    func saveSession(_ session: TrainingSession, gpsData: GPSData) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.date > $1.date }

        cacheGPSData(gpsData, for: session.id)
        persistGPSData(gpsData)

        // GPS データからスプリント回数を計算して上書き
        let count = SessionDataManager.calculateSprintCount(from: gpsData)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].sprintCount = count
        }

        // GPS データからアジリティ（方向転換）を検出
        let agilityEvents = SessionDataManager.detectAgilityEventsFromGPS(gpsData.points)
        let agilityTurnCount = agilityEvents.count
        let agilityScore: Int
        if agilityEvents.isEmpty {
            agilityScore = 0
        } else {
            let avgAngle = agilityEvents.map(\.magnitude).reduce(0, +) / Double(agilityEvents.count)
            // 60°=0点、180°=100点でスコア化
            agilityScore = max(0, min(100, Int((avgAngle - 60.0) / 120.0 * 100)))
        }
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx].agilityTurnCount = agilityTurnCount
            sessions[idx].agilityScore = agilityScore
        }
        saveAgilityData(AgilityData(sessionId: session.id, events: agilityEvents))
        print("✅ GPSアジリティ検出完了: \(agilityTurnCount)回, スコア=\(agilityScore)")

        persistSessions()

        print("✅ セッション保存完了: \(session.name), スプリント: \(count)回")
        print("📊 総セッション数: \(sessions.count)")
    }

    /// 年齢・性別に応じたスプリント開始閾値を返す（m/s）
    static func sprintThreshold(age: Int?, gender: Gender?) -> Double {
        let g = gender ?? .male
        let a = age ?? 25

        switch (g, a) {
        case (.female, ..<20):   return 4.72  // 17.0 km/h
        case (.female, 20..<40): return 4.72
        case (.female, 40..<50): return 4.17  // 15.0 km/h
        case (.female, 50..<60): return 3.89  // 14.0 km/h
        case (.female, 60...):   return 3.33  // 12.0 km/h

        case (_, ..<20):   return 5.56  // 20.0 km/h
        case (_, 20..<40): return 5.56
        case (_, 40..<50): return 5.00  // 18.0 km/h
        case (_, 50..<60): return 4.44  // 16.0 km/h
        case (_, 60...):   return 3.89  // 14.0 km/h

        default: return 5.56
        }
    }

    /// GPS データからスプリント回数を計算する
    static func calculateSprintCount(from gpsData: GPSData) -> Int {
        let sprintThreshold = sprintThreshold(
            age: UserProfileManager.shared.age,
            gender: UserProfileManager.shared.profile.gender
        )
        let sprintEndThreshold = sprintThreshold * 0.72
        let minSprintDuration: TimeInterval = 2.0
        let minSprintInterval: TimeInterval = 5.0

        var count = 0
        var isInSprint = false
        var isInSprintCandidate = false
        var candidateStartTime: Date? = nil
        var lastSprintEndTime: Date? = nil

        for point in gpsData.points {
            let speed = point.speed
            let timestamp = point.timestamp

            if isInSprint {
                if speed < sprintEndThreshold {
                    isInSprint = false
                    lastSprintEndTime = timestamp
                }
            } else if isInSprintCandidate {
                if speed < sprintEndThreshold {
                    isInSprintCandidate = false
                    candidateStartTime = nil
                } else if let start = candidateStartTime,
                          timestamp.timeIntervalSince(start) >= minSprintDuration {
                    isInSprint = true
                    isInSprintCandidate = false
                    count += 1
                }
            } else {
                if speed >= sprintThreshold {
                    let canStart = lastSprintEndTime == nil ||
                        timestamp.timeIntervalSince(lastSprintEndTime!) >= minSprintInterval
                    if canStart {
                        isInSprintCandidate = true
                        candidateStartTime = timestamp
                    }
                }
            }
        }

        return count
    }

    /// 時間帯別運動量を5分単位で集計（非永続化）
    static func computeTimeSeries(
        gpsPoints: [GPSPoint],
        intervalSeconds: TimeInterval = 300
    ) -> [TimeSeriesBucket] {
        guard let first = gpsPoints.first, let last = gpsPoints.last else { return [] }
        let totalDuration = last.timestamp.timeIntervalSince(first.timestamp)
        guard totalDuration > 0 else { return [] }

        let bucketCount = max(1, Int(ceil(totalDuration / intervalSeconds)))
        var distances   = [Double](repeating: 0, count: bucketCount)
        var maxSpeeds   = [Double](repeating: 0, count: bucketCount)
        var sprintCounts = [Int](repeating: 0, count: bucketCount)

        let threshold = sprintThreshold(
            age: UserProfileManager.shared.age,
            gender: UserProfileManager.shared.profile.gender
        )
        var isInSprint = false

        for i in gpsPoints.indices {
            let point = gpsPoints[i]
            let elapsed = point.timestamp.timeIntervalSince(first.timestamp)
            let b = min(Int(elapsed / intervalSeconds), bucketCount - 1)

            // 距離（前点との差分）
            if i > 0 {
                let prev = gpsPoints[i - 1]
                let prevElapsed = prev.timestamp.timeIntervalSince(first.timestamp)
                let prevB = min(Int(prevElapsed / intervalSeconds), bucketCount - 1)
                if prevB == b && point.speed >= 0.3 {
                    let loc1 = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
                    let loc2 = CLLocation(latitude: point.latitude, longitude: point.longitude)
                    distances[b] += loc1.distance(from: loc2)
                }
            }

            // 最高速度
            if point.speed > maxSpeeds[b] { maxSpeeds[b] = point.speed }

            // スプリント回数（開始検出）
            let wasInSprint = isInSprint
            if point.speed >= threshold { isInSprint = true }
            else if point.speed < threshold * 0.72 { isInSprint = false }
            if !wasInSprint && isInSprint { sprintCounts[b] += 1 }
        }

        return (0..<bucketCount).map { i in
            let bucketStart = Double(i) * intervalSeconds
            let durationSeconds = min(intervalSeconds, totalDuration - bucketStart)
            return TimeSeriesBucket(
                id: i,
                startMinute: i * Int(intervalSeconds / 60),
                distance: distances[i],
                sprintCount: sprintCounts[i],
                maxSpeed: maxSpeeds[i],
                durationSeconds: durationSeconds
            )
        }
    }

    /// スタミナ低下率を計算（後半/前半の「距離÷実時間」レートの比率）
    /// 最終バケットは5分未満になりうるため、バケット数の単純平均ではなく実時間で重み付けする
    /// （そうしないと短い最終バケットが後半平均を不当に押し下げてしまう）
    /// 返値: 0.85未満なら後半スタミナ低下とみなす
    static func computeStaminaDropRate(buckets: [TimeSeriesBucket]) -> Double? {
        guard buckets.count >= 2 else { return nil }
        let mid = buckets.count / 2
        let firstBuckets = buckets[0..<mid]
        let secondBuckets = buckets[mid...]

        let firstDuration = firstBuckets.map(\.durationSeconds).reduce(0, +)
        let secondDuration = secondBuckets.map(\.durationSeconds).reduce(0, +)
        guard firstDuration > 0, secondDuration > 0 else { return nil }

        let firstRate = firstBuckets.map(\.distance).reduce(0, +) / firstDuration
        let secondRate = secondBuckets.map(\.distance).reduce(0, +) / secondDuration
        guard firstRate > 0 else { return nil }
        return secondRate / firstRate
    }

    /// サード別滞在割合を計算（守備/中盤/攻撃、永続化しない）
    static func computeThirdRatios(
        gpsData: GPSData,
        field: Field,
        isFlipped: Bool
    ) -> (defensive: Double, middle: Double, attacking: Double) {
        var defensiveCount = 0
        var middleCount    = 0
        var attackingCount = 0

        for point in gpsData.points {
            guard let fieldCoord = field.convertToFieldCoordinate(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else { continue }

            let fy = isFlipped
                ? field.dimensions.length - fieldCoord.y
                : fieldCoord.y

            let length = field.dimensions.length
            if fy < length / 3 {
                defensiveCount += 1
            } else if fy < length * 2 / 3 {
                middleCount += 1
            } else {
                attackingCount += 1
            }
        }

        let total = defensiveCount + middleCount + attackingCount
        guard total > 0 else { return (0, 0, 0) }
        return (
            defensive: Double(defensiveCount) / Double(total) * 100,
            middle:    Double(middleCount)    / Double(total) * 100,
            attacking: Double(attackingCount) / Double(total) * 100
        )
    }

    // MARK: - Style Sync Analysis

    /// プロスタイルを2段階で診断する
    /// - ステップ1: ヒートマップの空間類似度のみでポジション（カテゴリ）を判定
    /// - ステップ2: 判定済みポジション内のスタイルを、スタッツ類似度50% + サード滞在比率50%でタイプ判定
    static func computeStyleSync(
        gpsData: GPSData,
        field: Field,
        isFlipped: Bool,
        sprintCount: Int,
        agilityTurnCount: Int?,
        maxSpeed: Double
    ) -> StyleSyncDiagnosis? {
        guard !gpsData.points.isEmpty else { return nil }

        let userGrid    = computeHeatmapGrid(gpsData: gpsData, field: field, isFlipped: isFlipped)
        let userSprint  = min(Double(sprintCount) / 30.0, 1.0)
        let userAgility = agilityTurnCount.map { min(Double($0) / 50.0, 1.0) }
        let userSpeed   = min(maxSpeed / 8.0, 1.0)
        let userThirds  = computeThirdRatios(gpsData: gpsData, field: field, isFlipped: isFlipped)

        // ステップ1: ヒートマップ（空間類似度）のみでポジションを判定
        let spatialByStyle: [(style: ProStyle, spatialSim: Double)] = ProStyle.all.map { style in
            let idealGrid = generateIdealHeatmap(style: style)
            return (style, cosineSimilarity(userGrid, idealGrid))
        }
        let positionScoreByCategory = Dictionary(grouping: spatialByStyle, by: { $0.style.category })
            .mapValues { entries in entries.map(\.spatialSim).max() ?? 0 }
        guard let topCategory = positionScoreByCategory.max(by: { $0.value < $1.value }) else { return nil }
        let position = PositionSyncResult(category: topCategory.key, positionScore: topCategory.value * 100.0)

        // ステップ2: 判定済みポジション内で、スタッツ類似度50% + サード滞在比率50%でタイプを判定
        let typeResults = ProStyle.all
            .filter { $0.category == topCategory.key }
            .map { style -> StyleSyncResult in
                let sprintScore  = max(0.0, 1.0 - abs(userSprint  - style.sprintTarget)  * 2)
                let agilityScore = userAgility.map { max(0.0, 1.0 - abs($0 - style.agilityTarget) * 2) } ?? 0.5
                let speedScore   = max(0.0, 1.0 - abs(userSpeed   - style.maxSpeedTarget) * 2)
                let statsSim     = (sprintScore + agilityScore + speedScore) / 3.0

                let defScore = max(0.0, 1.0 - abs(userThirds.defensive / 100.0 - style.defensiveThird) * 2)
                let midScore = max(0.0, 1.0 - abs(userThirds.middle    / 100.0 - style.middleThird)    * 2)
                let attScore = max(0.0, 1.0 - abs(userThirds.attacking / 100.0 - style.attackingThird) * 2)
                let thirdSim = (defScore + midScore + attScore) / 3.0

                let typeSim = statsSim * 0.5 + thirdSim * 0.5
                return StyleSyncResult(style: style, syncRate: typeSim * 100.0)
            }
            .sorted { $0.syncRate > $1.syncRate }

        return StyleSyncDiagnosis(position: position, typeResults: typeResults)
    }

    /// GPSデータから28×40のヒートマップグリッドを生成（コサイン類似度計算用）
    private static func computeHeatmapGrid(
        gpsData: GPSData,
        field: Field,
        isFlipped: Bool
    ) -> [[Double]] {
        let gridRows = 28  // fy方向（守備→攻撃）
        let gridCols = 40  // fx方向（左→右）
        var grid = Array(repeating: Array(repeating: 0.0, count: gridCols), count: gridRows)
        let sigma: Double = 1.5
        let kernelRadius  = 4

        for point in gpsData.points {
            guard let fc = field.convertToFieldCoordinate(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else { continue }
            let fx = isFlipped ? field.dimensions.width  - fc.x : fc.x
            let fy = isFlipped ? field.dimensions.length - fc.y : fc.y
            let row = Int((fy / field.dimensions.length) * Double(gridRows)).clamped(to: 0..<gridRows)
            let col = Int((fx / field.dimensions.width)  * Double(gridCols)).clamped(to: 0..<gridCols)
            for dr in -kernelRadius...kernelRadius {
                for dc in -kernelRadius...kernelRadius {
                    let r = row + dr; let c = col + dc
                    guard r >= 0, r < gridRows, c >= 0, c < gridCols else { continue }
                    let d = sqrt(Double(dr * dr + dc * dc))
                    grid[r][c] += exp(-(d * d) / (2.0 * sigma * sigma))
                }
            }
        }
        return grid
    }

    /// スタイル定義から理想ヒートマップを生成
    private static func generateIdealHeatmap(style: ProStyle) -> [[Double]] {
        let gridRows = 28  // fy方向（row=0: 守備, row=27: 攻撃）
        let gridCols = 40  // fx方向（col=0: 左, col=39: 右）
        var grid = Array(repeating: Array(repeating: 0.0, count: gridCols), count: gridRows)

        // ゾーン中心（row方向、27を3分割）
        let defCenter = 4.5;  let midCenter = 13.5;  let attCenter = 22.5
        let sigmaRow = 2.0 + style.heatmapSpread * 6.0
        let sigmaCol = 3.0 + style.heatmapSpread * 8.0
        let centerCol = 19.5  // フィールド横方向の中心

        for r in 0..<gridRows {
            for c in 0..<gridCols {
                let rD = Double(r); let cD = Double(c)
                // 縦方向: ゾーン比率でガウス重み
                let rowW = style.defensiveThird * exp(-pow(rD - defCenter, 2) / (2 * sigmaRow * sigmaRow))
                         + style.middleThird    * exp(-pow(rD - midCenter, 2) / (2 * sigmaRow * sigmaRow))
                         + style.attackingThird * exp(-pow(rD - attCenter, 2) / (2 * sigmaRow * sigmaRow))
                // 横方向: lateralBiasをそのまま「アウトサイド質量比率」として使用（左右対称）
                let outsideRatio = style.lateralBias
                let ctrW  = exp(-pow(cD - centerCol, 2) / (2 * sigmaCol * sigmaCol))
                let leftW = exp(-pow(cD - 5.0,       2) / (2 * sigmaCol * sigmaCol))
                let rgtW  = exp(-pow(cD - 34.0,      2) / (2 * sigmaCol * sigmaCol))
                let colW = (1.0 - outsideRatio) * ctrW + outsideRatio * (leftW + rgtW) / 2.0
                grid[r][c] = rowW * colW
            }
        }
        let mx = grid.flatMap { $0 }.max() ?? 1.0
        if mx > 0 { for r in 0..<gridRows { for c in 0..<gridCols { grid[r][c] /= mx } } }
        return grid
    }

    /// 2Dグリッドのコサイン類似度 (0-1)
    private static func cosineSimilarity(_ a: [[Double]], _ b: [[Double]]) -> Double {
        let aFlat = a.flatMap { $0 }
        let bFlat = b.flatMap { $0 }
        guard aFlat.count == bFlat.count else { return 0 }
        let dot  = zip(aFlat, bFlat).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = sqrt(aFlat.reduce(0.0) { $0 + $1 * $1 })
        let magB = sqrt(bFlat.reduce(0.0) { $0 + $1 * $1 })
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }

    // MARK: - Player Radar Analysis

    /// 6軸評価からレーダーチャートデータとプレイヤータイプを計算
    ///
    /// 参照値:
    ///   走力  : 130 m/分（実績参考集計P90=127.2 m/分ベース、2026-07-20見直し。旧100は90分換算の
    ///           アマチュアサッカー研究値だったが、実際のトレーニングセッション（短時間・高強度）は
    ///           試合平均より単位時間あたりの運動量が高く、旧値ではP50時点で頭打ちしていた）
    ///   スプリント: 1.0 回/分（実績参考集計P90=0.86 回/分ベース、2026-07-20見直し。旧0.4は
    ///           P50時点で既に超過し頭打ちしていた。判明当初は参考集計P90=0.33で妥当に見えたが、
    ///           `session.sprintCount`（記録時点の古い年齢デフォルトの閾値で計算された値）を
    ///           アップロードしていたバグが別途見つかり、現在の年齢基準の閾値で再計算した正しい値に
    ///           修正した結果、実際のレートはこれより大幅に高いことが判明した）
    ///   アジリティ: 4.5 回/分（実績参考集計P90=4.23 回/分ベース、2026-07-20見直し。旧3.0は
    ///           P75時点で既に超過し頭打ちしていた）
    ///   スタミナ : スタミナ低下率（時間非依存）
    ///   高強度  : 高強度HR時間率 100%（時間非依存、2026-07-20見直し。旧40%はP50時点で2倍以上
    ///           超過し常に頭打ちだった。高強度HR時間率は本人の推定最大心拍数に対する割合という
    ///           「本人内で完結する相対指標」であり、走力・アジリティのような他者と比較可能な絶対量
    ///           ではない（同じ運動量でも鍛えられた人ほど心拍は上がりにくい）。そのため他軸のように
    ///           母集団の分布からMaxを較正するのではなく、指標が元々取りうる範囲の上限である100%を
    ///           Maxとし、「自分がどれだけ追い込んだか」を測る軸として扱う）
    ///   最高速度 : 8.0 m/s ≈ 29 km/h（時間非依存）
    ///
    /// 走力・アジリティの見直し根拠は`RadarReferenceStatsView`（開発者用参考画面）およびSupabase RPC
    /// `get_radar_reference_stats()`の実績集計。2026-07-20時点ではn=6・単一ユーザーのみのサンプルで、
    /// テスターが増え次第再確認が必要（詳細は§17.2）。
    static func computePlayerRadar(
        totalDistance: Double,
        duration: TimeInterval,
        sprintCount: Int,
        agilityTurnCount: Int?,
        staminaDrop: Double?,
        hrIntensityRatio: Double?,
        maxSpeed: Double
    ) -> PlayerRadarData {
        let minutes = max(duration / 60.0, 1.0)

        // 時間正規化メトリクス（分あたり実績 ÷ 分あたり参照値）
        let distanceScore  = min((totalDistance / minutes) / 130.0, 1.0)
        let sprintScore    = min((Double(sprintCount) / minutes) / 1.0, 1.0)
        let agilityScore   = min((Double(agilityTurnCount ?? 0) / minutes) / 4.5, 1.0)

        // 時間非依存メトリクス
        let staminaScore   = min(staminaDrop ?? 0, 1.0)
        let intensityScore = min((hrIntensityRatio ?? 0) / 100.0, 1.0)
        let topSpeedScore  = min(maxSpeed / 8.0, 1.0)  // 8 m/s ≈ 29 km/h = 1.0

        let scores: [Double] = [distanceScore, sprintScore, agilityScore, staminaScore, intensityScore, topSpeedScore]
        let overall = scores.reduce(0, +) / Double(scores.count) * 100.0

        let types: [PlayerType] = [.longRunner, .sprinter, .agile, .stamina, .hardWorker, .speedster]
        let maxIdx = scores.indices.max(by: { scores[$0] < scores[$1] }) ?? 0

        return PlayerRadarData(
            distance:     distanceScore,
            sprint:       sprintScore,
            agility:      agilityScore,
            stamina:      staminaScore,
            intensity:    intensityScore,
            topSpeed:     topSpeedScore,
            playerType:   types[maxIdx],
            overallScore: overall
        )
    }

    // MARK: - AI監督フィードバック（§20.2）

    /// AI監督フィードバック用のセッションサマリーテキストを生成する。
    /// GPS生データは渡さず、既に計算済みの統計値をテキストに整形するだけで、
    /// 新たな計算は行わない（§20.2）。
    static func buildFeedbackSummaryText(
        session: TrainingSession,
        thirdRatios: (defensive: Double, middle: Double, attacking: Double),
        staminaDropRate: Double?,
        radar: PlayerRadarData,
        sprintCount: Int
    ) -> String {
        let minutes = max(session.duration / 60.0, 1.0)

        var lines: [String] = []
        lines.append(String(format: "- 実施時間: %.0f分", minutes))
        lines.append(String(
            format: "- 総移動距離: %dm（1分あたり約%dm。実施時間が短いセッションもあるため、量的指標は必ずこの実施時間を基準に判断すること）",
            Int(session.totalDistance), Int(session.totalDistance / minutes)
        ))
        lines.append(String(format: "- 最高速度: %.1f m/s", session.maxSpeed))
        lines.append(String(format: "- 平均速度: %.1f m/s", session.avgSpeed))
        lines.append("- スプリント回数: \(sprintCount)回")
        lines.append(String(
            format: "- サード別滞在割合: 守備%.0f%% / 中盤%.0f%% / 攻撃%.0f%%",
            thirdRatios.defensive, thirdRatios.middle, thirdRatios.attacking
        ))
        if let staminaDropRate {
            lines.append(String(
                format: "- 後半の運動量: 前半比%.0f%%（後半平均/前半平均の走行距離比）",
                staminaDropRate * 100
            ))
        }
        lines.append("- プレイヤータイプ: \(radar.playerType.rawValue)（総合スコア\(Int(radar.overallScore))点）")
        return lines.joined(separator: "\n")
    }

    // MARK: - Heart Rate Intensity Analysis

    /// 年齢から最大心拍数を推定
    /// 49歳以下: 標準式 (220 - age)  /  50歳以上: Tanaka式 (208 - 0.7 × age)
    static func maxHeartRate(age: Int) -> Double {
        if age < 50 {
            return Double(220 - age)
        } else {
            return 208.0 - 0.7 * Double(age)
        }
    }

    /// HR付きGPSPointsから高強度割合・高強度スプリント回数を計算
    /// - Returns: (highIntensityRatio: 0–100%, highIntensitySprintCount)
    ///   HRデータが存在しない場合は nil を返す
    static func computeHeartRateIntensity(
        gpsPoints: [GPSPoint],
        age: Int
    ) -> (highIntensityRatio: Double, highIntensitySprintCount: Int)? {
        let hrPoints = gpsPoints.compactMap { $0.heartRate }
        guard !hrPoints.isEmpty else { return nil }

        let maxHR = maxHeartRate(age: age)
        let threshold = maxHR * 0.80

        // 高強度割合
        let highCount = hrPoints.filter { $0 >= threshold }.count
        let ratio = Double(highCount) / Double(hrPoints.count) * 100.0

        // 高強度スプリント回数：スプリント区間の中でHR >= 80%maxHR の区間を数える
        let sprintSegments = computeSprintSegments(gpsPoints)
        var highIntensitySprints = 0
        for seg in sprintSegments {
            let segPoints = Array(gpsPoints[seg.startIndex...seg.endIndex])
            let segHR = segPoints.compactMap { $0.heartRate }
            if !segHR.isEmpty {
                let avgHR = segHR.reduce(0, +) / Double(segHR.count)
                if avgHR >= threshold { highIntensitySprints += 1 }
            }
        }

        return (highIntensityRatio: ratio, highIntensitySprintCount: highIntensitySprints)
    }

    /// GPS速度からスプリント区間を検出して返す（非永続化・毎回再計算）
    static func computeSprintSegments(_ gpsPoints: [GPSPoint]) -> [SprintSegment] {
        let threshold = sprintThreshold(
            age: UserProfileManager.shared.age,
            gender: UserProfileManager.shared.profile.gender
        )
        let endThreshold = threshold * 0.72
        let minDuration: TimeInterval = 1.0

        var segments: [SprintSegment] = []
        var sprintStart: Int? = nil

        for i in 0..<gpsPoints.count {
            let speed = gpsPoints[i].speed
            if sprintStart == nil && speed >= threshold {
                sprintStart = i
            } else if let start = sprintStart, speed < endThreshold {
                let duration = gpsPoints[i].timestamp.timeIntervalSince(gpsPoints[start].timestamp)
                if duration >= minDuration {
                    let maxSpeed = gpsPoints[start...i].map(\.speed).max() ?? 0
                    var dist = 0.0
                    for j in start..<i {
                        let a = gpsPoints[j], b = gpsPoints[j + 1]
                        let loc1 = CLLocation(latitude: a.latitude, longitude: a.longitude)
                        let loc2 = CLLocation(latitude: b.latitude, longitude: b.longitude)
                        dist += loc1.distance(from: loc2)
                    }
                    segments.append(SprintSegment(startIndex: start, endIndex: i,
                                                  maxSpeed: maxSpeed, distance: dist))
                }
                sprintStart = nil
            }
        }
        return segments
    }

    // MARK: - Trim (打ち切り)

    /// 経過秒（先頭点からの秒数）に対応する points 内インデックスを二分探索で返す
    static func gpsIndex(in points: [GPSPoint], atElapsed offset: TimeInterval) -> Int {
        guard let first = points.first else { return 0 }
        var lo = 0
        var hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if points[mid].timestamp.timeIntervalSince(first.timestamp) <= offset {
                lo = mid
            } else {
                hi = mid - 1
            }
        }
        return lo
    }

    /// offset までの GPS 点列を返す。offset が nil、または points が空ならそのまま返す（トリムなし）
    static func trimmedPoints(_ points: [GPSPoint], toOffset offset: TimeInterval?) -> [GPSPoint] {
        guard let offset, !points.isEmpty else { return points }
        return Array(points[0...gpsIndex(in: points, atElapsed: offset)])
    }

    /// トリム設定を適用した「有効な」GPSデータを返す。生ファイルは変更しない
    func getEffectiveGPSData(for session: TrainingSession) -> GPSData? {
        guard let full = getGPSData(for: session.id) else { return nil }
        return GPSData(sessionId: full.sessionId, points: SessionDataManager.trimmedPoints(full.points, toOffset: session.effectiveEndOffset))
    }

    /// from〜to（先頭点からの経過秒、[from, to]）の範囲でGPS点列を切り出す
    static func slicedPoints(_ points: [GPSPoint], from startOffset: TimeInterval, to endOffset: TimeInterval) -> [GPSPoint] {
        guard !points.isEmpty else { return [] }
        let startIndex = gpsIndex(in: points, atElapsed: startOffset)
        let endIndex = gpsIndex(in: points, atElapsed: endOffset)
        guard endIndex >= startIndex else { return [] }
        return Array(points[startIndex...endIndex])
    }

    /// GPS点列の部分区間から算出した全メトリクス（トリム・ドリル分割の両方で共有）
    struct SegmentStats {
        let duration: TimeInterval
        let totalDistance: Double
        let maxSpeed: Double
        let avgSpeed: Double
        let sprintCount: Int
        let agilityTurnCount: Int
        let agilityScore: Int
        let staminaDrop: Double?
        let hrIntensityRatio: Double?
        let sprintSegments: [SprintSegment]
        let timeSeries: [TimeSeriesBucket]
        let hrIntensity: (highIntensityRatio: Double, highIntensitySprintCount: Int)?
    }

    /// points に対して全メトリクスを計算する。points.count < 2 なら nil（算出不可）
    static func computeSegmentStats(points: [GPSPoint]) -> SegmentStats? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        let timeSeries = computeTimeSeries(gpsPoints: points)
        let totalDistance = timeSeries.map(\.distance).reduce(0, +)
        let maxSpeed = points.map(\.speed).max() ?? 0
        let avgSpeed = duration > 0 ? totalDistance / duration : 0
        let sprintSegments = computeSprintSegments(points)
        let staminaDrop = computeStaminaDropRate(buckets: timeSeries)
        let hrIntensity = UserProfileManager.shared.age.flatMap {
            computeHeartRateIntensity(gpsPoints: points, age: $0)
        }
        let agilityEvents = detectAgilityEventsFromGPS(points)
        let agilityScore: Int
        if agilityEvents.isEmpty {
            agilityScore = 0
        } else {
            let avgAngle = agilityEvents.map(\.magnitude).reduce(0, +) / Double(agilityEvents.count)
            agilityScore = max(0, min(100, Int((avgAngle - 60.0) / 120.0 * 100)))
        }

        return SegmentStats(
            duration: duration, totalDistance: totalDistance, maxSpeed: maxSpeed, avgSpeed: avgSpeed,
            sprintCount: sprintSegments.count, agilityTurnCount: agilityEvents.count, agilityScore: agilityScore,
            staminaDrop: staminaDrop, hrIntensityRatio: hrIntensity?.highIntensityRatio,
            sprintSegments: sprintSegments, timeSeries: timeSeries, hrIntensity: hrIntensity
        )
    }

    // MARK: - Drill Split (ドリル自動分割)

    /// セッションに対し、フィールド境界の外＋低速度の滞留からドリル休憩を自動検出する。
    /// セッションに既に fieldId が紐付いていればそのフィールドを優先的に使い、
    /// 未紐付けなら GPS 点列からの自動判定（`detectField`）にフォールバックする。
    /// フィールドが特定できない、または休憩が2区間未満（=分割不要）の場合は何もしない。
    ///
    /// Watch→iPhone転送直後だけでなく、フィールドが後から登録・更新された場合や
    /// セッションに手動でフィールドが紐付けられた場合にも再実行される（`reanalyzeSessionsForDrillSplits`,
    /// `updateFieldId` から呼ばれる）。転送時点でフィールド未登録だと最初の解析は何も検出できないため。
    func analyzeForDrillSplits(sessionId: String) {
        guard let session = sessions.first(where: { $0.id == sessionId }),
              let gpsData = getGPSData(for: sessionId) else { return }

        let field: Field?
        if let fieldId = session.fieldId {
            field = FieldManager.shared.getField(by: fieldId)
        } else {
            field = FieldManager.shared.detectField(for: gpsData.points)
        }
        guard let field else { return }

        let breaks = DrillSplitDetector.detectBreaks(points: gpsData.points, field: field)
        let ranges = DrillSplitDetector.segmentRanges(totalDuration: session.duration, breaks: breaks)
        guard ranges.count >= 2 else { return }

        setPendingSplitBreaks(for: sessionId, breaks: breaks)
        print("🏃 ドリル自動分割候補を検出: sessionId=\(sessionId) 検出本数=\(ranges.count)")
    }

    /// まだドリル分割を解析していない（=一度も検出されなかった、または対象フィールド未登録だった）
    /// セッションをまとめて再解析する。フィールドの新規登録・更新のたびに呼ばれる。
    func reanalyzeSessionsForDrillSplits() {
        for session in sessions where session.pendingSplitBreaks == nil && !session.isSupersededBySplit {
            analyzeForDrillSplits(sessionId: session.id)
        }
    }

    /// ドリル自動分割の検出結果を保存（コーチの確認待ち）
    func setPendingSplitBreaks(for sessionId: String, breaks: [DrillBreakInterval]) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].pendingSplitBreaks = breaks
        persistSessions()
    }

    /// 検出された分割候補を破棄し、1本のセッションのまま残す
    func dismissPendingSplit(for sessionId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].pendingSplitBreaks = nil
        persistSessions()
    }

    /// 検出されたドリル分割を確定する。生トレースを区間ごとに切り出し、それぞれを独立した
    /// TrainingSession として保存・Supabaseアップロードする。元の結合セッションは削除せず
    /// supersededBySplit フラグでソフト除外する（分割ミスがあった場合に復旧可能にするため）。
    func confirmDrillSplit(for sessionId: String) async {
        guard let original = sessions.first(where: { $0.id == sessionId }),
              let breaks = original.pendingSplitBreaks, !breaks.isEmpty,
              let rawGPS = getGPSData(for: sessionId) else { return }

        let ranges = DrillSplitDetector.segmentRanges(totalDuration: original.duration, breaks: breaks)
        guard ranges.count >= 2 else {
            dismissPendingSplit(for: sessionId)
            return
        }

        for (i, range) in ranges.enumerated() {
            let points = SessionDataManager.slicedPoints(rawGPS.points, from: range.start, to: range.end)
            guard let stats = SessionDataManager.computeSegmentStats(points: points) else { continue }

            let newSession = TrainingSession(
                userId: original.userId,
                teamId: original.teamId,
                fieldId: original.fieldId,
                name: "\(original.name) - ドリル\(i + 1)",
                date: original.date.addingTimeInterval(range.start),
                duration: stats.duration,
                visibility: original.visibility,
                totalDistance: stats.totalDistance,
                maxSpeed: stats.maxSpeed,
                avgSpeed: stats.avgSpeed,
                isFlipped: original.isFlipped,
                staminaDrop: stats.staminaDrop,
                hrIntensityRatio: stats.hrIntensityRatio,
                splitFromSessionId: original.id
            )

            // saveSession が GPS データから sprintCount / agility を再計算して確定させる
            saveSession(newSession, gpsData: GPSData(sessionId: newSession.id, points: points))

            // stale コピーを使わず、saveSession が確定させた最新の状態を sessions 配列から読み直してアップロードする
            guard let saved = sessions.first(where: { $0.id == newSession.id }) else { continue }
            let radar = SessionDataManager.computePlayerRadar(
                totalDistance: saved.totalDistance,
                duration: saved.duration,
                sprintCount: saved.sprintCount ?? 0,
                agilityTurnCount: saved.agilityTurnCount,
                staminaDrop: saved.staminaDrop,
                hrIntensityRatio: saved.hrIntensityRatio,
                maxSpeed: saved.maxSpeed
            )
            do {
                try await SupabaseManager.shared.uploadSessionSummary(saved, radar: radar)
                print("✅ 分割セッションのSupabaseアップロード完了: id=\(saved.id)")
            } catch {
                print("❌ 分割セッションのSupabaseアップロード失敗: id=\(saved.id) error=\(error)")
            }
        }

        if let index = sessions.firstIndex(where: { $0.id == sessionId }) {
            sessions[index].supersededBySplit = true
            sessions[index].pendingSplitBreaks = nil
            persistSessions()
        }
        print("✅ ドリル分割確定完了: 元sessionId=\(sessionId) 分割数=\(ranges.count)")
    }

    /// ドリル分割を元に戻す。分割で作られたセッション（ドリルN）をすべて削除し、
    /// 元の結合セッションのsupersededBySplitを解除して一覧・平均計算に復帰させる
    func restoreSplit(originalSessionId: String) {
        // 先にsupersededBySplitを解除しておく。deleteSession側の「最後の1本を消したら元セッションも
        // 道連れで削除する」カスケードは isSupersededBySplit を条件にしているため、先に解除しておくことで
        // 以下のループで最後のドリルを削除した際に元セッションが誤って削除されるのを防ぐ
        if let index = sessions.firstIndex(where: { $0.id == originalSessionId }) {
            sessions[index].supersededBySplit = nil
            persistSessions()
        }

        let splitSessions = sessions.filter { $0.splitFromSessionId == originalSessionId }
        for splitSession in splitSessions {
            deleteSession(splitSession)
        }

        print("↩️ ドリル分割を元に戻しました: 元sessionId=\(originalSessionId) 削除したドリル数=\(splitSessions.count)")
    }

    /// このセッションを削除すると、分割グループの最後の1本のため元の結合セッションも
    /// 道連れで削除されることになるか（削除前の確認UIで使う）
    func deletingSessionWouldAlsoDeleteOriginal(_ session: TrainingSession) -> Bool {
        guard let splitFromSessionId = session.splitFromSessionId,
              let original = sessions.first(where: { $0.id == splitFromSessionId }),
              original.isSupersededBySplit else { return false }
        return !sessions.contains { $0.id != session.id && $0.splitFromSessionId == splitFromSessionId }
    }

    /// GPSデータを取得
    func getGPSData(for sessionId: String) -> GPSData? {
        if let cached = gpsDataCache[sessionId] {
            // キャッシュヒット: LRU 順を更新
            lruOrder.removeAll { $0 == sessionId }
            lruOrder.append(sessionId)
            return cached
        }

        // キャッシュミス: ファイルから読み込んでキャッシュに追加
        if let loaded = loadGPSData(sessionId: sessionId) {
            cacheGPSData(loaded, for: sessionId)
            return loaded
        }

        return nil
    }

    /// セッションを削除
    func deleteSession(_ session: TrainingSession) {
        let shouldCascadeDeleteOriginal = deletingSessionWouldAlsoDeleteOriginal(session)

        sessions.removeAll { $0.id == session.id }
        gpsDataCache.removeValue(forKey: session.id)
        lruOrder.removeAll { $0 == session.id }

        persistSessions()
        deleteGPSData(sessionId: session.id)
        deleteAgilityData(sessionId: session.id)

        print("🗑️ セッション削除: \(session.name)")

        // 分割グループの最後の1本だった場合、隠れて二度と復元できなくなる元セッションを
        // 残さないよう、元セッションもまとめて削除する
        if shouldCascadeDeleteOriginal, let splitFromSessionId = session.splitFromSessionId,
           let original = sessions.first(where: { $0.id == splitFromSessionId }) {
            deleteSession(original)
        }
    }

    // MARK: - iCloud Backup Setting

    /// iCloudバックアップの有効/無効を取得
    var isICloudBackupEnabled: Bool {
        UserDefaults.standard.bool(forKey: iCloudBackupEnabledKey)
    }

    /// iCloudバックアップの有効/無効を変更し、ディレクトリの設定を即時反映
    func setICloudBackupEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: iCloudBackupEnabledKey)
        updateBackupExclusion(excluded: !enabled)
    }

    // MARK: - Persistence (Sessions)

    private func persistSessions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let encoded = try? encoder.encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else {
            print("📂 保存されたセッションなし")
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([TrainingSession].self, from: data) {
            sessions = decoded
            print("📂 \(sessions.count)件のセッションを読み込みました")
        }
    }

    // MARK: - Persistence (GPS Data — File System)

    private func persistGPSData(_ gpsData: GPSData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(gpsData) else { return }
        let url = gpsFileURL(for: gpsData.sessionId)
        try? data.write(to: url, options: .atomic)
    }

    private func loadGPSData(sessionId: String) -> GPSData? {
        let url = gpsFileURL(for: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GPSData.self, from: data)
    }

    private func deleteGPSData(sessionId: String) {
        // ファイルが存在しない場合は無視（エラーとして扱わない）
        try? FileManager.default.removeItem(at: gpsFileURL(for: sessionId))
    }

    // MARK: - Agility Data

    private var agilityDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FootballGPS/agility", isDirectory: true)
    }

    private func agilityFileURL(for sessionId: String) -> URL {
        agilityDirectory.appendingPathComponent("agilitydata_\(sessionId).json")
    }

    private func ensureAgilityDirectoryExists() {
        let dir = agilityDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func saveAgilityData(_ data: AgilityData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let encoded = try? encoder.encode(data) else { return }
        try? encoded.write(to: agilityFileURL(for: data.sessionId), options: .atomic)
    }

    func loadAgilityData(sessionId: String) -> AgilityData? {
        let url = agilityFileURL(for: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgilityData.self, from: data)
    }

    private func deleteAgilityData(sessionId: String) {
        try? FileManager.default.removeItem(at: agilityFileURL(for: sessionId))
    }

    /// Watch から受信した rawMotion JSON ファイルを受け取る
    /// アジリティ検出は GPS ベースに移行したため、ここでは受信ログのみ記録
    func processRawMotionFile(_ srcURL: URL, sessionId: String) {
        Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: srcURL),
                  let samples = try? JSONDecoder().decode([RawMotionSample].self, from: data) else {
                print("❌ rawMotion ファイル読み込み失敗: \(srcURL.lastPathComponent)")
                return
            }
            print("📳 rawMotion 受信: \(samples.count) サンプル (sessionId=\(sessionId)) ※アジリティはGPS判定済み")
        }
    }

    /// GPS 点列から方向転換イベントを検出
    ///
    /// 条件:
    ///   - 速度 ≥ 1.5 m/s（ジョギング以上）
    ///   - 方向変化角 ≥ 60°
    ///   - GPS精度 ≤ 20 m
    ///   - イベント間隔 ≥ 1.5 秒（連続誤検知防止）
    ///
    /// magnitude には方向変化角（度）を格納する。スコアは 60°=0, 180°=100 で線形換算。
    static func detectAgilityEventsFromGPS(_ points: [GPSPoint]) -> [AgilityEvent] {
        guard points.count >= 3 else { return [] }

        let minSpeed: Double        = 1.5   // m/s
        let minAngleDeg: Double     = 60.0  // 度
        let minEventInterval: TimeInterval = 1.5  // 秒
        let maxAccuracy: Double     = 20.0  // m
        let latToM: Double          = 111_000.0

        var events: [AgilityEvent] = []
        var lastEventTime: Date?   = nil

        for i in 1..<(points.count - 1) {
            let prev = points[i - 1]
            let curr = points[i]
            let next = points[i + 1]

            guard curr.horizontalAccuracy <= maxAccuracy else { continue }
            guard curr.speed >= minSpeed else { continue }
            if let last = lastEventTime,
               curr.timestamp.timeIntervalSince(last) < minEventInterval { continue }

            // 経度を実距離（m）に換算してから角度計算
            let lonToM = 111_000.0 * cos(curr.latitude * .pi / 180.0)
            let dx1 = (curr.longitude - prev.longitude) * lonToM
            let dy1 = (curr.latitude  - prev.latitude)  * latToM
            let dx2 = (next.longitude - curr.longitude) * lonToM
            let dy2 = (next.latitude  - curr.latitude)  * latToM

            let mag1 = sqrt(dx1 * dx1 + dy1 * dy1)
            let mag2 = sqrt(dx2 * dx2 + dy2 * dy2)
            guard mag1 > 0.1, mag2 > 0.1 else { continue }

            let cosAngle = min(max((dx1 * dx2 + dy1 * dy2) / (mag1 * mag2), -1.0), 1.0)
            let angleDeg = acos(cosAngle) * 180.0 / .pi

            guard angleDeg >= minAngleDeg else { continue }

            events.append(AgilityEvent(timestamp: curr.timestamp, magnitude: angleDeg))
            lastEventTime = curr.timestamp
        }

        print("📍 GPSアジリティ検出: \(events.count)回 (対象点数: \(points.count))")
        return events
    }

    /// B方式ヒステリシス検出: 開始閾値 2.5G / 終了閾値 0.5G が 0.5秒継続
    private static nonisolated func detectAgilityEventsFromRawMotion(_ samples: [RawMotionSample]) -> [AgilityEvent] {
        let startThreshold = 2.5
        let endThreshold = 0.5
        let quietDuration = 0.5

        var events: [AgilityEvent] = []
        var isInEvent = false
        var peakMagnitude = 0.0
        var peakTimestamp: TimeInterval = 0
        var quietStart: TimeInterval? = nil

        for sample in samples {
            let magnitude = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)

            if isInEvent {
                if magnitude > peakMagnitude {
                    peakMagnitude = magnitude
                    peakTimestamp = sample.timestamp
                }
                if magnitude < endThreshold {
                    if let qs = quietStart {
                        if sample.timestamp - qs >= quietDuration {
                            events.append(AgilityEvent(
                                timestamp: Date(timeIntervalSince1970: peakTimestamp),
                                magnitude: peakMagnitude
                            ))
                            isInEvent = false
                            quietStart = nil
                            peakMagnitude = 0.0
                        }
                    } else {
                        quietStart = sample.timestamp
                    }
                } else {
                    quietStart = nil
                }
            } else {
                if magnitude > startThreshold {
                    isInEvent = true
                    peakMagnitude = magnitude
                    peakTimestamp = sample.timestamp
                    quietStart = nil
                }
            }
        }
        return events
    }

    // MARK: - GPS Directory

    private var gpsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FootballGPS/gps", isDirectory: true)
    }

    private func gpsFileURL(for sessionId: String) -> URL {
        gpsDirectory.appendingPathComponent("gpsdata_\(sessionId).json")
    }

    /// GPS ディレクトリを作成し、バックアップ除外設定を適用
    private func ensureGPSDirectoryExists() {
        let dir = gpsDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        updateBackupExclusion(excluded: !isICloudBackupEnabled)
    }

    /// iCloud バックアップ除外フラグを GPS ディレクトリに設定
    private func updateBackupExclusion(excluded: Bool) {
        var url = gpsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try? url.setResourceValues(values)
    }

    // MARK: - LRU Cache

    /// LRU キャッシュに GPS データを追加（最大3件を超えたら最古エントリを除去）
    private func cacheGPSData(_ gpsData: GPSData, for sessionId: String) {
        gpsDataCache[sessionId] = gpsData
        lruOrder.removeAll { $0 == sessionId }
        lruOrder.append(sessionId)

        while lruOrder.count > maxCacheSize {
            let evicted = lruOrder.removeFirst()
            gpsDataCache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Migration (UserDefaults → File System)

    /// 旧 UserDefaults 形式の GPS データをファイルシステムへ移行
    private func migrateGPSDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let sessionIds = sessions.map { $0.id }

        // 移行すべき UserDefaults エントリが存在するか事前確認
        let idsToMigrate = sessionIds.filter {
            UserDefaults.standard.data(forKey: "gpsData_\($0)") != nil
        }

        guard !idsToMigrate.isEmpty else {
            // 移行対象なし（初回インストール等）: フラグだけ立てて完了
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        isMigrating = true
        let gpsDir = gpsDirectory

        Task.detached(priority: .utility) { [idsToMigrate, gpsDir] in
            for sessionId in idsToMigrate {
                let udKey = "gpsData_\(sessionId)"
                // UserDefaults に保存された生 JSON データをそのままファイルへコピー
                guard let data = UserDefaults.standard.data(forKey: udKey) else { continue }

                let fileURL = gpsDir.appendingPathComponent("gpsdata_\(sessionId).json")
                guard (try? data.write(to: fileURL, options: .atomic)) != nil,
                      FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                // 書き出し成功を確認してから UserDefaults を削除
                UserDefaults.standard.removeObject(forKey: udKey)
            }

            UserDefaults.standard.set(true, forKey: "gpsDataMigrationCompleted")

            await MainActor.run {
                SessionDataManager.shared.isMigrating = false
                print("✅ GPSデータのファイルシステム移行完了")
            }
        }
    }

    // MARK: - Utilities

    /// UserDefaultsから最新データを再読み込み（Pull-to-Refresh用）
    func reloadSessions() {
        loadSessions()
        print("🔄 セッション再読み込み完了: \(sessions.count)件")
    }

    /// セッションのフィールドIDを更新（ユーザーが手動選択したとき、または自動選択が成功したとき）
    func updateFieldId(for sessionId: String, fieldId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].fieldId = fieldId
        persistSessions()
        print("✅ フィールド紐付け更新: sessionId=\(sessionId) -> fieldId=\(fieldId)")

        // フィールドが判明したことで、未解析だったドリル分割を再解析する
        if sessions[index].pendingSplitBreaks == nil && !sessions[index].isSupersededBySplit {
            analyzeForDrillSplits(sessionId: sessionId)
        }
    }

    /// fieldId未設定のセッションに対し、GPS点列から`FieldManager.detectField`で一致するフィールドを
    /// 探し、見つかれば`updateFieldId`で自動的に永続化する（ユーザーの手動選択を待たない）。
    /// `updateFieldId`が内部で`analyzeForDrillSplits`の再解析も連鎖して行うため、ここでは呼ばない
    /// （再帰防止: このメソッドは `analyzeForDrillSplits` / `updateFieldId` からは呼び出さない）
    @discardableResult
    func autoAssignFieldId(for sessionId: String) -> Bool {
        guard let session = sessions.first(where: { $0.id == sessionId }), session.fieldId == nil,
              let gpsData = getGPSData(for: sessionId),
              let field = FieldManager.shared.detectField(for: gpsData.points) else { return false }
        updateFieldId(for: sessionId, fieldId: field.id)
        print("📍 フィールド自動選択: sessionId=\(sessionId) -> fieldId=\(field.id)")
        return true
    }

    /// まだ fieldId が未確定のセッションをまとめて自動選択を試みる。
    /// フィールドの新規登録・境界編集のたびに呼ばれる
    func autoAssignFieldIdForUnresolvedSessions() {
        for session in sessions where session.fieldId == nil {
            autoAssignFieldId(for: session.id)
        }
    }

    /// セッションのコート入れ替えフラグを更新
    func updateIsFlipped(for sessionId: String, isFlipped: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].isFlipped = isFlipped
        persistSessions()
    }

    /// セッション詳細閲覧時に算出した派生メトリクスを永続化
    func updateComputedMetrics(for sessionId: String, staminaDrop: Double?, hrIntensityRatio: Double?, sprintCount: Int? = nil) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].staminaDrop = staminaDrop
        sessions[index].hrIntensityRatio = hrIntensityRatio
        if let sprintCount {
            sessions[index].sprintCount = sprintCount
        }
        persistSessions()
    }

    /// 自己平均への採用フラグを更新
    func updateExcludeFromAverage(for sessionId: String, excluded: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].excludeFromAverage = excluded
        persistSessions()
    }

    /// 打ち切り（トリム）設定と、トリム後の点列から再計算した派生メトリクスをまとめて永続化する。
    /// effectiveEndOffset に nil を渡すと「元に戻す」になる（トリムなし・生データ全体で再計算した値を書き戻す）
    func applyTrim(
        for sessionId: String,
        effectiveEndOffset: TimeInterval?,
        duration: TimeInterval,
        totalDistance: Double,
        maxSpeed: Double,
        avgSpeed: Double,
        sprintCount: Int,
        agilityTurnCount: Int,
        agilityScore: Int,
        staminaDrop: Double?,
        hrIntensityRatio: Double?
    ) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].effectiveEndOffset = effectiveEndOffset
        sessions[index].duration = duration
        sessions[index].totalDistance = totalDistance
        sessions[index].maxSpeed = maxSpeed
        sessions[index].avgSpeed = avgSpeed
        sessions[index].sprintCount = sprintCount
        sessions[index].agilityTurnCount = agilityTurnCount
        sessions[index].agilityScore = agilityScore
        sessions[index].staminaDrop = staminaDrop
        sessions[index].hrIntensityRatio = hrIntensityRatio
        persistSessions()
    }

    /// すべてのデータをクリア（開発用）
    func clearAllData() {
        for session in sessions {
            deleteGPSData(sessionId: session.id)
        }
        sessions.removeAll()
        gpsDataCache.removeAll()
        lruOrder.removeAll()
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        print("🗑️ すべてのデータをクリアしました")
    }

    // MARK: - Simulator Support

    #if targetEnvironment(simulator)
    /// シミュレーター用: Watch側から保存されたデータを読み込む
    private func loadPendingSessionsFromWatch() {
        guard let pendingIds = UserDefaults.standard.stringArray(forKey: "pendingSessionIds"),
              !pendingIds.isEmpty else { return }

        print("🔄 Watch側から保留中のセッションを読み込み中... (\(pendingIds.count)件)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loadedCount = 0

        for sessionId in pendingIds {
            guard let sessionData = UserDefaults.standard.data(forKey: "pendingSession_\(sessionId)"),
                  let session = try? decoder.decode(TrainingSession.self, from: sessionData) else {
                print("⚠️ セッション読み込み失敗: \(sessionId)")
                continue
            }
            guard let gpsDataEncoded = UserDefaults.standard.data(forKey: "pendingGPS_\(sessionId)"),
                  let gpsData = try? decoder.decode(GPSData.self, from: gpsDataEncoded) else {
                print("⚠️ GPSデータ読み込み失敗: \(sessionId)")
                continue
            }

            saveSession(session, gpsData: gpsData)
            loadedCount += 1

            UserDefaults.standard.removeObject(forKey: "pendingSession_\(sessionId)")
            UserDefaults.standard.removeObject(forKey: "pendingGPS_\(sessionId)")
        }

        UserDefaults.standard.removeObject(forKey: "pendingSessionIds")
        UserDefaults.standard.synchronize()

        if loadedCount > 0 {
            print("✅ Watch側から\(loadedCount)件のセッションを読み込みました")
        }
    }
    #endif

    // MARK: - Calibration Data (Debug)

    #if DEBUG
    var calibrationDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FootballGPS/calibration", isDirectory: true)
    }

    func clearCalibrationFiles() {
        let dir = calibrationDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        print("🗑️ キャリブレーションCSV削除: \(files.count)件")
    }

    func saveCalibrationFile(from sourceURL: URL, filename: String) {
        let dir = calibrationDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let destURL = dir.appendingPathComponent(filename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            print("✅ キャリブレーションCSV保存: \(filename)")
        } catch {
            print("❌ キャリブレーションCSV保存失敗: \(error)")
        }
    }

    // MARK: - Agility Detection (Debug)

    /// キャリブレーション用アジリティイベント（peakMagnitude のみ）
    struct CalibrationAgilityEvent {
        let peakMagnitude: Double
    }

    /// アジリティメトリクス集計結果
    struct AgilityMetrics {
        let eventCount: Int
        let avgPeakMagnitude: Double
        let score: Double // 0.0 〜 1.0
    }

    /// B方式ヒステリシス検出: 8.0G超でイベント開始、0.5G未満が0.5秒継続でイベント終了
    static func detectAgilityEvents(from samples: [CalibrationSample]) -> [CalibrationAgilityEvent] {
        let startThreshold = 8.0
        let endThreshold = 0.5
        let quietDuration = 0.5

        var events: [CalibrationAgilityEvent] = []
        var isInEvent = false
        var peakMagnitude = 0.0
        var quietStart: TimeInterval? = nil

        for sample in samples {
            let magnitude = sqrt(sample.accX * sample.accX + sample.accY * sample.accY + sample.accZ * sample.accZ)

            if isInEvent {
                peakMagnitude = max(peakMagnitude, magnitude)
                if magnitude < endThreshold {
                    if let qs = quietStart {
                        if sample.timestamp - qs >= quietDuration {
                            events.append(CalibrationAgilityEvent(peakMagnitude: peakMagnitude))
                            isInEvent = false
                            quietStart = nil
                            peakMagnitude = 0.0
                        }
                    } else {
                        quietStart = sample.timestamp
                    }
                } else {
                    quietStart = nil
                }
            } else {
                if magnitude > startThreshold {
                    isInEvent = true
                    peakMagnitude = magnitude
                    quietStart = nil
                }
            }
        }

        return events
    }

    /// アジリティイベント群からスコアと統計を計算（8.0G基準）
    static func computeAgilityMetrics(from events: [CalibrationAgilityEvent]) -> AgilityMetrics {
        let lowerBound = 8.0
        let upperBound = 15.0

        guard !events.isEmpty else {
            return AgilityMetrics(eventCount: 0, avgPeakMagnitude: 0, score: 0)
        }

        let avgPeak = events.map { $0.peakMagnitude }.reduce(0, +) / Double(events.count)
        let score = max(0.0, min(1.0, (avgPeak - lowerBound) / (upperBound - lowerBound)))

        return AgilityMetrics(eventCount: events.count, avgPeakMagnitude: avgPeak, score: score)
    }
    #endif
}
