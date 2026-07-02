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

    func uploadSessionSummary(_ session: TrainingSession) async throws {
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
            agilityEventCount: nil,
            agilityPeakG: nil,
            heartRate: session.heartRate,
            activeCaloriesKcal: session.activeCalories
        )
        try await client.from("session_summaries").insert(row).execute()
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
        let agilityPeakG: Double?
        let heartRate: Double?
        let activeCaloriesKcal: Double?

        enum CodingKeys: String, CodingKey {
            case userId             = "user_id"
            case localSessionId     = "local_session_id"
            case sessionName        = "session_name"
            case sessionDate        = "session_date"
            case durationSeconds    = "duration_seconds"
            case totalDistanceMeters = "total_distance_meters"
            case maxSpeedMs         = "max_speed_ms"
            case avgSpeedMs         = "avg_speed_ms"
            case sprintCount        = "sprint_count"
            case agilityEventCount  = "agility_event_count"
            case agilityPeakG       = "agility_peak_g"
            case heartRate          = "heart_rate"
            case activeCaloriesKcal = "active_calories_kcal"
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
