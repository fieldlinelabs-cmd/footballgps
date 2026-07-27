//
//  SupabaseManager.swift
//  FootballGPS
//

import Foundation
import Supabase

class SupabaseManager {
    static let shared = SupabaseManager()

    private let client: SupabaseClient

    private init() {
        let urlString = Bundle.main.infoDictionary?["SUPABASE_URL"] as? String
            ?? "https://cpbczeugekezejumretu.supabase.co"
        let key = Bundle.main.infoDictionary?["SUPABASE_ANON_KEY"] as? String
            ?? "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNwYmN6ZXVnZWtlemVqdW1yZXR1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI0ODA5MzEsImV4cCI6MjA5ODA1NjkzMX0.Jb9g7plWefuGXQM0fs9BfRO61ExZN9wf0KnnHPA31t8"
        client = SupabaseClient(supabaseURL: URL(string: urlString)!, supabaseKey: key)
    }

    /// 現在の認証ユーザーID
    var currentUserId: UUID? {
        client.auth.currentSession?.user.id
    }

    // MARK: - Auth

    /// 匿名認証を保証し、UserProfileManager のIDを同期する（§14.3.2）
    func ensureAuthenticated() async throws {
        if client.auth.currentSession == nil {
            try await client.auth.signInAnonymously()
        }
        if let uid = client.auth.currentSession?.user.id.uuidString {
            await MainActor.run {
                UserProfileManager.shared.syncId(with: uid)
            }
            // users テーブルに upsert して FK 制約に備える
            let profile = await MainActor.run { UserProfileManager.shared.profile }
            try? await upsertUser(profile)
        }
    }

    // MARK: - users テーブル

    func upsertUser(_ profile: UserProfile) async throws {
        guard let userId = currentUserId else { return }
        let row = UserRow(
            id: userId,
            displayName: profile.displayName,
            birthDate: profile.birthDate.map { isoDateString($0) },
            gender: profile.gender?.rawValue
        )
        try await client.from("users").upsert(row).execute()
    }

    // MARK: - session_summaries テーブル

    func uploadSessionSummary(_ session: TrainingSession, radar: PlayerRadarData) async throws {
        guard let userId = currentUserId else {
            print("❌ uploadSessionSummary: currentUserIdがnilのためアップロードをスキップ: session=\(session.id)")
            return
        }
        let row = SessionSummaryRow(
            userId: userId,
            localSessionId: session.id,
            sessionName: session.name,
            sessionDate: ISO8601DateFormatter().string(from: session.date),
            durationSeconds: session.duration,
            totalDistanceMeters: session.totalDistance,
            maxSpeedMs: session.maxSpeed,
            avgSpeedMs: session.avgSpeed,
            sprintCount: session.sprintCount,
            agilityEventCount: session.agilityTurnCount,
            heartRate: session.heartRate,
            activeCaloriesKcal: session.activeCalories,
            staminaDrop: session.staminaDrop,
            hrIntensityRatio: session.hrIntensityRatio,
            radarDistance: radar.distance,
            radarSprint: radar.sprint,
            radarAgility: radar.agility,
            radarStamina: radar.stamina,
            radarIntensity: radar.intensity,
            radarTopSpeed: radar.topSpeed,
            radarOverallScore: radar.overallScore,
            playerType: radar.playerType.rawValue
        )
        try await client.from("session_summaries").upsert(row, onConflict: "user_id,local_session_id").execute()
    }

    // MARK: - calibration_results テーブル

    func uploadCalibrationResult(
        age: Int?,
        gender: Gender?,
        maxSpeed: Double?,
        agilityPeakG: Double?,
        agilityEventCount: Int?
    ) async throws {
        guard let userId = currentUserId else { return }
        let row = CalibrationResultRow(
            userId: userId,
            recordedAt: ISO8601DateFormatter().string(from: Date()),
            ageAtRecording: age,
            gender: gender?.rawValue,
            maxSpeedMs: maxSpeed,
            maxSpeedKmh: maxSpeed.map { $0 * 3.6 },
            agilityPeakG: agilityPeakG,
            agilityEventCount: agilityEventCount
        )
        try await client.from("calibration_results").insert(row).execute()
    }

    // MARK: - RPC: 年代・性別ごとの集計

    func fetchCalibrationStats() async throws -> [AgeGroupStats] {
        let rows: [CalibrationStatRow] = try await client
            .rpc("get_calibration_stats")
            .execute()
            .value
        return rows.map { row in
            AgeGroupStats(
                ageGroup: row.ageGroup,
                gender: row.gender ?? "",
                count: Int(row.n),
                medianSpeedKmh: row.medianKmh,
                p25SpeedKmh: row.p25Kmh,
                p75SpeedKmh: row.p75Kmh,
                medianAgilityG: row.medianG
            )
        }
    }

    // MARK: - RPC: レーダーチャートMax基準値の参考集計（§24 開発者用）

    /// session_summaries に溜まった実績データから、レーダー各軸の分布（p50/p75/p90）を返す。
    /// この値は開発者がMax定数（SessionDataManager.computePlayerRadar）を見直す際の参考であり、
    /// アプリが自動でMaxに反映するものではない。
    func fetchRadarReferenceStats() async throws -> RadarReferenceStats {
        let rows: [RadarReferenceStatRow] = try await client
            .rpc("get_radar_reference_stats")
            .execute()
            .value
        guard let row = rows.first else {
            return RadarReferenceStats(n: 0, distance: .zero, sprint: .zero, agility: .zero, hrIntensity: .zero, maxSpeed: .zero)
        }
        return RadarReferenceStats(
            n: row.n,
            distance: Percentiles(p50: row.distancePerMinP50, p75: row.distancePerMinP75, p90: row.distancePerMinP90),
            sprint: Percentiles(p50: row.sprintPerMinP50, p75: row.sprintPerMinP75, p90: row.sprintPerMinP90),
            agility: Percentiles(p50: row.agilityPerMinP50, p75: row.agilityPerMinP75, p90: row.agilityPerMinP90),
            hrIntensity: Percentiles(p50: row.hrIntensityRatioP50, p75: row.hrIntensityRatioP75, p90: row.hrIntensityRatioP90),
            maxSpeed: Percentiles(p50: row.maxSpeedMsP50, p75: row.maxSpeedMsP75, p90: row.maxSpeedMsP90)
        )
    }

    struct Percentiles {
        let p50: Double?
        let p75: Double?
        let p90: Double?

        static let zero = Percentiles(p50: nil, p75: nil, p90: nil)
    }

    struct RadarReferenceStats {
        let n: Int
        let distance: Percentiles     // m/分
        let sprint: Percentiles       // 回/分
        let agility: Percentiles      // 回/分
        let hrIntensity: Percentiles  // %
        let maxSpeed: Percentiles     // m/s
    }

    private struct RadarReferenceStatRow: Decodable {
        let n: Int
        let distancePerMinP50: Double?
        let distancePerMinP75: Double?
        let distancePerMinP90: Double?
        let sprintPerMinP50: Double?
        let sprintPerMinP75: Double?
        let sprintPerMinP90: Double?
        let agilityPerMinP50: Double?
        let agilityPerMinP75: Double?
        let agilityPerMinP90: Double?
        let hrIntensityRatioP50: Double?
        let hrIntensityRatioP75: Double?
        let hrIntensityRatioP90: Double?
        let maxSpeedMsP50: Double?
        let maxSpeedMsP75: Double?
        let maxSpeedMsP90: Double?

        enum CodingKeys: String, CodingKey {
            case n
            case distancePerMinP50 = "distance_per_min_p50"
            case distancePerMinP75 = "distance_per_min_p75"
            case distancePerMinP90 = "distance_per_min_p90"
            case sprintPerMinP50   = "sprint_per_min_p50"
            case sprintPerMinP75   = "sprint_per_min_p75"
            case sprintPerMinP90   = "sprint_per_min_p90"
            case agilityPerMinP50  = "agility_per_min_p50"
            case agilityPerMinP75  = "agility_per_min_p75"
            case agilityPerMinP90  = "agility_per_min_p90"
            case hrIntensityRatioP50 = "hr_intensity_ratio_p50"
            case hrIntensityRatioP75 = "hr_intensity_ratio_p75"
            case hrIntensityRatioP90 = "hr_intensity_ratio_p90"
            case maxSpeedMsP50     = "max_speed_ms_p50"
            case maxSpeedMsP75     = "max_speed_ms_p75"
            case maxSpeedMsP90     = "max_speed_ms_p90"
        }
    }

    // MARK: - AgeGroupStats（CalibrationStatsView と共有）

    struct AgeGroupStats: Identifiable {
        let id = UUID()
        let ageGroup: String
        let gender: String
        let count: Int
        let medianSpeedKmh: Double
        let p25SpeedKmh: Double
        let p75SpeedKmh: Double
        let medianAgilityG: Double?
    }

    // MARK: - AI監督フィードバック（§20）

    /// 広告表示前に呼び、生成の「予約チケット」を発行する（§20.5.1, §24）。
    /// `purpose`で機能を区別する（省略時はAI監督フィードバック向けの"coach_feedback"）。
    func createAdTicket(
        localSessionId: String,
        persona: String? = nil,
        purpose: String = "coach_feedback"
    ) async throws -> String {
        struct RequestBody: Encodable {
            let localSessionId: String
            let persona: String?
            let purpose: String
        }
        struct ResponseBody: Decodable {
            let ticketId: String
        }
        let response: ResponseBody = try await client.functions.invoke(
            "create-ad-ticket",
            options: FunctionInvokeOptions(
                body: RequestBody(localSessionId: localSessionId, persona: persona, purpose: purpose)
            )
        )
        return response.ticketId
    }

    /// AI監督フィードバックを生成する（§20.5.3）。`ticketId` が nil の場合は fail-open
    /// （広告なし、1日3回まで。§20.6参照）として扱われる。
    func fetchAICoachFeedback(
        ticketId: String?,
        localSessionId: String,
        persona: String,
        position: String?,
        sessionSummary: String
    ) async throws -> AICoachFeedbackResult {
        struct RequestBody: Encodable {
            let ticketId: String?
            let localSessionId: String
            let persona: String
            let position: String?
            let sessionSummary: String
        }
        struct ErrorBody: Decodable {
            let error: AICoachFeedbackError
        }

        do {
            return try await client.functions.invoke(
                "ai-coach-feedback",
                options: FunctionInvokeOptions(
                    body: RequestBody(
                        ticketId: ticketId,
                        localSessionId: localSessionId,
                        persona: persona,
                        position: position,
                        sessionSummary: sessionSummary
                    )
                )
            )
        } catch let error as FunctionsError {
            if case .httpError(_, let data) = error,
               let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw body.error
            }
            throw error
        }
    }

    /// セッション×監督の生成履歴を新しい順に取得する（履歴チップ表示用、§20.6）。
    /// 広告・API呼び出しを伴わない無料の再閲覧。
    func fetchCachedFeedbacks(localSessionId: String) async throws -> [AICoachFeedbackRow] {
        guard let userId = currentUserId else { return [] }
        return try await client
            .from("ai_coach_feedbacks")
            .select()
            .eq("user_id", value: userId)
            .eq("local_session_id", value: localSessionId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    // MARK: - 二つ名生成（§24）

    /// 二つ名を生成する。`ticketId` が nil の場合は fail-open として扱われる（ai-coach-feedbackと同様）。
    func fetchNickname(
        ticketId: String?,
        localSessionId: String,
        sessionSummary: String
    ) async throws -> NicknameResult {
        struct RequestBody: Encodable {
            let ticketId: String?
            let localSessionId: String
            let sessionSummary: String
        }
        struct ErrorBody: Decodable {
            let error: AICoachFeedbackError
        }

        do {
            return try await client.functions.invoke(
                "ai-nickname",
                options: FunctionInvokeOptions(
                    body: RequestBody(
                        ticketId: ticketId,
                        localSessionId: localSessionId,
                        sessionSummary: sessionSummary
                    )
                )
            )
        } catch let error as FunctionsError {
            if case .httpError(_, let data) = error,
               let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw body.error
            }
            throw error
        }
    }

    /// セッションを問わず最新の二つ名を1件取得する（プレイヤーデータ画面ヘッダーの称号表示用）。
    func fetchLatestNickname() async throws -> NicknameRow? {
        guard let userId = currentUserId else { return nil }
        let rows: [NicknameRow] = try await client
            .from("player_nicknames")
            .select()
            .eq("user_id", value: userId)
            .order("created_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    // MARK: - Private Helpers

    private func isoDateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    // MARK: - Encodable Row Types

    private struct UserRow: Encodable {
        let id: UUID
        let displayName: String
        let birthDate: String?
        let gender: String?

        enum CodingKeys: String, CodingKey {
            case id
            case displayName = "display_name"
            case birthDate   = "birth_date"
            case gender
        }
    }

    private struct SessionSummaryRow: Encodable {
        let userId: UUID
        let localSessionId: String
        let sessionName: String
        let sessionDate: String
        let durationSeconds: Double
        let totalDistanceMeters: Double
        let maxSpeedMs: Double
        let avgSpeedMs: Double
        let sprintCount: Int?
        let agilityEventCount: Int?
        let heartRate: Double?
        let activeCaloriesKcal: Double?
        let staminaDrop: Double?
        let hrIntensityRatio: Double?
        let radarDistance: Double
        let radarSprint: Double
        let radarAgility: Double
        let radarStamina: Double
        let radarIntensity: Double
        let radarTopSpeed: Double
        let radarOverallScore: Double
        let playerType: String

        enum CodingKeys: String, CodingKey {
            case userId              = "user_id"
            case localSessionId      = "local_session_id"
            case sessionName         = "session_name"
            case sessionDate         = "session_date"
            case durationSeconds     = "duration_seconds"
            case totalDistanceMeters = "total_distance_meters"
            case maxSpeedMs          = "max_speed_ms"
            case avgSpeedMs          = "avg_speed_ms"
            case sprintCount         = "sprint_count"
            case agilityEventCount   = "agility_event_count"
            case heartRate           = "heart_rate"
            case activeCaloriesKcal  = "active_calories_kcal"
            case staminaDrop         = "stamina_drop"
            case hrIntensityRatio    = "hr_intensity_ratio"
            case radarDistance       = "radar_distance"
            case radarSprint         = "radar_sprint"
            case radarAgility        = "radar_agility"
            case radarStamina        = "radar_stamina"
            case radarIntensity      = "radar_intensity"
            case radarTopSpeed       = "radar_top_speed"
            case radarOverallScore   = "radar_overall_score"
            case playerType          = "player_type"
        }
    }

    private struct CalibrationResultRow: Encodable {
        let userId: UUID
        let recordedAt: String
        let ageAtRecording: Int?
        let gender: String?
        let maxSpeedMs: Double?
        let maxSpeedKmh: Double?
        let agilityPeakG: Double?
        let agilityEventCount: Int?

        enum CodingKeys: String, CodingKey {
            case userId           = "user_id"
            case recordedAt       = "recorded_at"
            case ageAtRecording   = "age_at_recording"
            case gender
            case maxSpeedMs       = "max_speed_ms"
            case maxSpeedKmh      = "max_speed_kmh"
            case agilityPeakG     = "agility_peak_g"
            case agilityEventCount = "agility_event_count"
        }
    }

    // MARK: - Decodable RPC Response

    private struct CalibrationStatRow: Decodable {
        let ageGroup: String
        let gender: String?
        let n: Int
        let medianKmh: Double
        let p25Kmh: Double
        let p75Kmh: Double
        let medianG: Double?

        enum CodingKeys: String, CodingKey {
            case ageGroup  = "age_group"
            case gender
            case n
            case medianKmh = "median_kmh"
            case p25Kmh    = "p25_kmh"
            case p75Kmh    = "p75_kmh"
            case medianG   = "median_g"
        }
    }
}
