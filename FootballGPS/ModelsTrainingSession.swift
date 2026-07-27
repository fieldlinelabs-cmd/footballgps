//
//  TrainingSession.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation
import CoreLocation

/// トレーニングセッションのモデル
struct TrainingSession: Identifiable, Codable {
    let id: String
    let userId: String
    let teamId: String?
    var fieldId: String? // var に変更
    
    var name: String
    let date: Date
    var duration: TimeInterval // 秒
    
    // 公開設定
    var visibility: SessionVisibility
    
    // 統計データ
    var totalDistance: Double // メートル
    var maxSpeed: Double // m/s
    var avgSpeed: Double // m/s
    var sprintCount: Int?
    
    // コート入れ替え表示フラグ
    var isFlipped: Bool

    // GPSデータへのパス（Cloud Storageに保存）
    var gpsDataPath: String?

    // ヘルスケアデータ
    var heartRate: Double?       // セッション終了時点の心拍数 (bpm)
    var activeCalories: Double?  // セッション中の消費カロリー (kcal)

    // アジリティ検出結果（nil = 未処理 / rawMotionファイル未着）
    var agilityTurnCount: Int?
    var agilityScore: Int?

    // セッション詳細閲覧時に算出して永続化する派生メトリクス
    var staminaDrop: Double?      // 後半スタミナ低下率（0…1）
    var hrIntensityRatio: Double? // 高強度HR割合（0…100%）

    // 自己平均から手動除外するフラグ（nil = false として扱う、旧データとの後方互換用）
    var excludeFromAverage: Bool?

    /// 自己平均から除外されるか（手動 or 5分未満）
    var isExcludedFromAverage: Bool { excludeFromAverage ?? false }

    // トリム（打ち切り）設定: 先頭GPS点からの経過秒。nil = トリムなし（生データ全体を使用、旧データとの後方互換用）
    var effectiveEndOffset: TimeInterval?

    /// トリムが適用されているか
    var isTrimmed: Bool { effectiveEndOffset != nil }
    
    enum SessionVisibility: String, Codable {
        case `public` = "public"
        case `private` = "private"
        case teamAdminOnly = "team_admin_only"
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        teamId: String? = nil,
        fieldId: String? = nil,
        name: String? = nil,
        date: Date = Date(),
        duration: TimeInterval = 0,
        visibility: SessionVisibility = .private,
        totalDistance: Double = 0,
        maxSpeed: Double = 0,
        avgSpeed: Double = 0,
        sprintCount: Int? = nil,
        isFlipped: Bool = false,
        gpsDataPath: String? = nil,
        heartRate: Double? = nil,
        activeCalories: Double? = nil,
        agilityTurnCount: Int? = nil,
        agilityScore: Int? = nil,
        staminaDrop: Double? = nil,
        hrIntensityRatio: Double? = nil,
        excludeFromAverage: Bool? = nil
    ) {
        self.id = id
        self.userId = userId
        self.teamId = teamId
        self.fieldId = fieldId
        self.name = name ?? Self.defaultName(for: date)
        self.date = date
        self.duration = duration
        self.visibility = visibility
        self.totalDistance = totalDistance
        self.maxSpeed = maxSpeed
        self.avgSpeed = avgSpeed
        self.sprintCount = sprintCount
        self.isFlipped = isFlipped
        self.gpsDataPath = gpsDataPath
        self.heartRate = heartRate
        self.activeCalories = activeCalories
        self.agilityTurnCount = agilityTurnCount
        self.agilityScore = agilityScore
        self.staminaDrop = staminaDrop
        self.hrIntensityRatio = hrIntensityRatio
        self.excludeFromAverage = excludeFromAverage
    }
    
    /// デフォルトのセッション名（日時ベース）
    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    /// Firestoreとの変換用
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "name": name,
            "date": date.timeIntervalSince1970, // TimeIntervalに変換
            "duration": duration,
            "visibility": visibility.rawValue,
            "totalDistance": totalDistance,
            "maxSpeed": maxSpeed,
            "avgSpeed": avgSpeed
        ]
        
        if let teamId = teamId { dict["teamId"] = teamId }
        if let fieldId = fieldId { dict["fieldId"] = fieldId }
        if let sprintCount = sprintCount { dict["sprintCount"] = sprintCount }
        if let gpsDataPath = gpsDataPath { dict["gpsDataPath"] = gpsDataPath }
        if let heartRate = heartRate { dict["heartRate"] = heartRate }
        if let activeCalories = activeCalories { dict["activeCalories"] = activeCalories }

        return dict
    }
}

/// GPS座標データポイント
struct GPSPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speed: Double // m/s
    let altitude: Double // メートル
    let horizontalAccuracy: Double // 精度（メートル）
    var heartRate: Double?  // bpm（nil = HR データなし）

    init(timestamp: Date, latitude: Double, longitude: Double, speed: Double, altitude: Double, horizontalAccuracy: Double, heartRate: Double? = nil) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
        self.heartRate = heartRate
    }

    init(location: CLLocation, heartRate: Double? = nil) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.speed = max(0, location.speed)
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
        self.heartRate = heartRate
    }
}

/// GPSデータの配列（JSON保存用）
struct GPSData: Codable {
    let sessionId: String
    let points: [GPSPoint]
}

/// 加速度生データサンプル（Watch→iPhone転送用・非永続化）
struct RawMotionSample: Codable {
    let timestamp: TimeInterval  // Date().timeIntervalSince1970
    let x: Double                // userAcceleration.x [G]
    let y: Double                // userAcceleration.y [G]
    let z: Double                // userAcceleration.z [G]
}

/// スプリント区間（GPSデータから毎回再計算、非永続化）
struct SprintSegment {
    let startIndex: Int
    let endIndex: Int
    let maxSpeed: Double   // m/s
    let distance: Double   // m
}

/// アジリティイベント（永続化用）
struct AgilityEvent: Codable {
    let timestamp: Date
    let magnitude: Double  // 3軸合成ノルム [G]
}

/// アジリティデータ（永続化用）
struct AgilityData: Codable {
    let sessionId: String
    let events: [AgilityEvent]
}

/// 時間帯別運動量バケット（5分単位・非永続化）
struct TimeSeriesBucket: Identifiable {
    let id: Int            // バケットインデックス
    let startMinute: Int   // 区間開始（分）
    let distance: Double   // 区間走行距離 (m)
    let sprintCount: Int   // 区間スプリント回数
    let maxSpeed: Double   // 区間最高速度 (m/s)
    let durationSeconds: Double  // 区間の実際の長さ（秒）。最終バケットは5分未満になりうる
}

/// プロスタイル定義（ゾーンパラメータから理想ヒートマップを生成して類似度を計算）
struct ProStyle: Identifiable {
    let id: String
    let name: String
    let category: String        // CF / ウイング / センターハーフ / CB / SB
    let defensiveThird: Double  // 守備サード目標比率 (0-1)
    let middleThird:    Double  // 中盤サード目標比率 (0-1)
    let attackingThird: Double  // 攻撃サード目標比率 (0-1)
    let lateralBias:    Double  // 理想ヒートマップの左右対称アウトサイド質量比率 (0=完全に中央, 1=完全にアウトサイド)
    let sprintTarget:   Double  // スプリント目標 (0-1, 基準30回)
    let agilityTarget:  Double  // アジリティ目標 (0-1, 基準50回)
    let maxSpeedTarget: Double  // 最高速度目標 (0-1, 基準8m/s)
    let heatmapSpread:  Double  // 0=密集, 1=広域

    static let all: [ProStyle] = [
        // MARK: CF
        ProStyle(id: "striker",     name: "ストライカー",    category: "CF",
                 defensiveThird: 0.05, middleThird: 0.20, attackingThird: 0.75,
                 lateralBias: 0.10, sprintTarget: 0.70, agilityTarget: 0.40,
                 maxSpeedTarget: 0.88, heatmapSpread: 0.45),
        ProStyle(id: "target_man",  name: "ターゲットマン",  category: "CF",
                 defensiveThird: 0.05, middleThird: 0.15, attackingThird: 0.80,
                 lateralBias: 0.00, sprintTarget: 0.20, agilityTarget: 0.60,
                 maxSpeedTarget: 0.55, heatmapSpread: 0.20),
        // MARK: ウイング
        ProStyle(id: "winger_classic", name: "ウインガー（クラシック）", category: "ウイング",
                 defensiveThird: 0.10, middleThird: 0.30, attackingThird: 0.60,
                 lateralBias: 0.85, sprintTarget: 0.75, agilityTarget: 0.35,
                 maxSpeedTarget: 0.90, heatmapSpread: 0.40),
        ProStyle(id: "winger_modern", name: "ウインガー（現代型）",     category: "ウイング",
                 defensiveThird: 0.10, middleThird: 0.30, attackingThird: 0.60,
                 lateralBias: 0.70, sprintTarget: 0.50, agilityTarget: 0.70,
                 maxSpeedTarget: 0.75, heatmapSpread: 0.50),
        // MARK: センターハーフ
        ProStyle(id: "box_to_box",  name: "ボックス・トゥ・ボックス", category: "センターハーフ",
                 defensiveThird: 0.30, middleThird: 0.40, attackingThird: 0.30,
                 lateralBias: 0.10, sprintTarget: 0.70, agilityTarget: 0.50,
                 maxSpeedTarget: 0.65, heatmapSpread: 0.90),
        ProStyle(id: "regista",     name: "レジスタ",                category: "センターハーフ",
                 defensiveThird: 0.40, middleThird: 0.45, attackingThird: 0.15,
                 lateralBias: 0.05, sprintTarget: 0.20, agilityTarget: 0.40,
                 maxSpeedTarget: 0.50, heatmapSpread: 0.40),
        ProStyle(id: "balancer",    name: "バランサー",              category: "センターハーフ",
                 defensiveThird: 0.40, middleThird: 0.45, attackingThird: 0.15,
                 lateralBias: 0.10, sprintTarget: 0.55, agilityTarget: 0.45,
                 maxSpeedTarget: 0.60, heatmapSpread: 0.40),
        ProStyle(id: "game_maker",  name: "ゲームメーカー",          category: "センターハーフ",
                 defensiveThird: 0.15, middleThird: 0.45, attackingThird: 0.40,
                 lateralBias: 0.10, sprintTarget: 0.40, agilityTarget: 0.65,
                 maxSpeedTarget: 0.60, heatmapSpread: 0.50),
        // MARK: CB
        ProStyle(id: "libero",      name: "リベロ型",      category: "CB",
                 defensiveThird: 0.65, middleThird: 0.25, attackingThird: 0.10,
                 lateralBias: 0.05, sprintTarget: 0.40, agilityTarget: 0.45,
                 maxSpeedTarget: 0.55, heatmapSpread: 0.70),
        ProStyle(id: "stopper",     name: "ストッパー型",  category: "CB",
                 defensiveThird: 0.75, middleThird: 0.20, attackingThird: 0.05,
                 lateralBias: 0.05, sprintTarget: 0.20, agilityTarget: 0.70,
                 maxSpeedTarget: 0.50, heatmapSpread: 0.25),
        // MARK: SB
        ProStyle(id: "lateral",     name: "ラテラル",          category: "SB",
                 defensiveThird: 0.35, middleThird: 0.35, attackingThird: 0.30,
                 lateralBias: 0.80, sprintTarget: 0.70, agilityTarget: 0.50,
                 maxSpeedTarget: 0.75, heatmapSpread: 0.55),
        ProStyle(id: "false_sb",    name: "偽サイドバック",    category: "SB",
                 defensiveThird: 0.40, middleThird: 0.45, attackingThird: 0.15,
                 lateralBias: 0.40, sprintTarget: 0.50, agilityTarget: 0.65,
                 maxSpeedTarget: 0.60, heatmapSpread: 0.55),
        ProStyle(id: "solid_sb",    name: "堅実型サイドバック", category: "SB",
                 defensiveThird: 0.55, middleThird: 0.35, attackingThird: 0.10,
                 lateralBias: 0.80, sprintTarget: 0.30, agilityTarget: 0.45,
                 maxSpeedTarget: 0.55, heatmapSpread: 0.40),
    ]
}

/// プロスタイル類似度の計算結果（ステップ2: タイプ判定・スタッツ類似度のみ）
struct StyleSyncResult: Identifiable {
    var id: String { style.id }
    let style: ProStyle
    let syncRate: Double  // 0-100（スタッツ類似度のみ）
}

/// ステップ1: ポジション（カテゴリ）判定結果 — ヒートマップ空間類似度のみで算出
struct PositionSyncResult {
    let category: String        // CF / ウイング / センターハーフ / CB / SB
    let positionScore: Double   // 0-100（カテゴリ内スタイルの空間類似度の最大値）
}

/// プロスタイル診断の最終結果（ポジション→タイプの2段階判定）
struct StyleSyncDiagnosis {
    let position: PositionSyncResult
    let typeResults: [StyleSyncResult]  // 判定済みポジション内のスタイルをスタッツ類似度降順でソート
}

/// プレイヤータイプ称号（最高スコア軸で決定）
enum PlayerType: String {
    case longRunner = "ロングランナー"
    case sprinter   = "スプリンター"
    case agile      = "アジャイル型"
    case stamina    = "スタミナ型"
    case hardWorker = "ハードワーカー"
    case speedster  = "スピードスター"
}

/// レーダーチャート用プレイヤー評価データ（非永続化）
struct PlayerRadarData {
    let distance:     Double  // 0…1  基準: 10km
    let sprint:       Double  // 0…1  基準: 30回
    let agility:      Double  // 0…1  基準: 50回
    let stamina:      Double  // 0…1  基準: staminaDrop 1.0
    let intensity:    Double  // 0…1  基準: 高強度HR 40%
    let topSpeed:     Double  // 0…1  基準: 8 m/s（約29 km/h）
    let playerType:   PlayerType
    let overallScore: Double  // 0…100（6軸平均）
}

// MARK: - AI監督フィードバック（§20）

/// `ai-coach-feedback` Edge Functionの生成結果
struct AICoachFeedbackResult: Decodable {
    let positive: String
    let improvement: String
    let summary: String
    let personaRecognized: Bool
}

/// `ai_coach_feedbacks` テーブルの1行（履歴表示用）
struct AICoachFeedbackRow: Decodable, Identifiable {
    let id: UUID
    let persona: String
    let position: String?
    let positive: String
    let improvement: String
    let summary: String
    let personaRecognized: Bool
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case persona
        case position
        case positive
        case improvement
        case summary
        case personaRecognized = "persona_recognized"
        case createdAt = "created_at"
    }
}

/// `ai-coach-feedback` / `create-ad-ticket` Edge Functionが返すエラーコード（§20.5, §20.6）
enum AICoachFeedbackError: String, Decodable, Error {
    case ticketNotVerified      = "ticket_not_verified"
    case ticketExpired          = "ticket_expired"
    case ticketExhausted        = "ticket_exhausted"
    case invalidTicket          = "invalid_ticket"
    case dailyLimitReached      = "daily_limit_reached"
    case serviceBusy            = "service_busy"
    case contentBlocked         = "content_blocked"
    case unauthorized
    case invalidPersona         = "invalid_persona"
    case invalidPosition        = "invalid_position"
    case invalidSessionSummary  = "invalid_session_summary"
    case invalidParams          = "invalid_params"
    case geminiError            = "gemini_error"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = AICoachFeedbackError(rawValue: raw) ?? .unknown
    }

    /// §20.7 のUI仕様に対応するユーザー向けメッセージ
    var userMessage: String {
        switch self {
        case .ticketNotVerified, .invalidTicket:
            return "広告視聴の確認ができませんでした。もう一度お試しください。"
        case .ticketExpired, .ticketExhausted:
            return "広告視聴の有効期限が切れました。もう一度広告を見てお試しください。"
        case .dailyLimitReached:
            return "本日の無料生成枠を使い切りました。しばらくしてから広告視聴で分析するか、翌日以降にお試しください。"
        case .serviceBusy:
            return "現在アクセスが集中しています。しばらく時間をおいてから再度お試しください。"
        case .contentBlocked:
            return "不適切な内容が含まれていたため生成できませんでした。入力内容を確認してください。"
        case .invalidPersona, .invalidPosition, .invalidSessionSummary, .invalidParams:
            return "入力内容を確認してください。"
        case .unauthorized:
            return "認証エラーが発生しました。アプリを再起動してお試しください。"
        case .geminiError, .unknown:
            return "分析中にエラーが発生しました。もう一度お試しください。"
        }
    }
}

// MARK: - 二つ名生成（§24）

/// `ai-nickname` Edge Functionの生成結果
struct NicknameResult: Decodable {
    let nickname: String
    let reason: String
}

/// `player_nicknames` テーブルの1行（ヘッダー称号表示用）
struct NicknameRow: Decodable, Identifiable {
    let id: UUID
    let nickname: String
    let reason: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case nickname
        case reason
        case createdAt = "created_at"
    }
}

#if DEBUG
/// アジリティキャリブレーション用センサーサンプル
struct CalibrationSample: Codable {
    let timestamp: TimeInterval
    let tag: String
    let accX: Double
    let accY: Double
    let accZ: Double
    let gyroX: Double
    let gyroY: Double
    let gyroZ: Double
    let speed: Double
}
#endif
