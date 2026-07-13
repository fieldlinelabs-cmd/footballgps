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
        guard let userId = currentUserId else { return }
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
        try await client.from("session_summaries").upsert(row).execute()
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

    /// 広告表示前に呼び、生成の「予約チケット」を発行する（§20.5.1）
    func createAdTicket(localSessionId: String, persona: String) async throws -> String {
        struct RequestBody: Encodable {
            let localSessionId: String
            let persona: String
        }
        struct ResponseBody: Decodable {
            let ticketId: String
        }
        let response: ResponseBody = try await client.functions.invoke(
            "create-ad-ticket",
            options: FunctionInvokeOptions(
                body: RequestBody(localSessionId: localSessionId, persona: persona)
            )
        )
        return response.ticketId
    }

    /// AI監督フィードバックを生成する（§20.5.3）。`ticketId` が nil の場合は fail-open
    /// （広告なし、1日30回まで。TestFlightソロテスト期間中の緩和値。§20.6参照）として扱われる。
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
