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

    /// 匿名認証を保証し、UserProfileManager のIDを同期する（§14.3.2）。
    /// 起動時には呼ばず、AI機能（AI監督・二つ名）を使うときに初めて呼ぶ（2026-11-08変更、技術実装仕様書 §14.2）。
    /// そのため AI機能を使わない利用者は Supabase に何も送らない
    func ensureAuthenticated() async throws {
        if client.auth.currentSession == nil {
            try await client.auth.signInAnonymously()
        }
        if let uid = client.auth.currentSession?.user.id.uuidString {
            await MainActor.run {
                UserProfileManager.shared.syncId(with: uid)
            }
            // AI機能のテーブルが users を参照しているため、先に行を作っておく
            try? await upsertUser()
        }
    }

    // MARK: - users テーブル

    /// 送るのは匿名のIDだけ。表示名・生年月日・性別はサーバーで使っていないため送らない（技術実装仕様書 §14.2）
    func upsertUser() async throws {
        guard let userId = currentUserId else { return }
        try await client.from("users").upsert(UserRow(id: userId)).execute()
    }

    // MARK: - AI監督フィードバック（§20）

    /// 広告表示前に呼び、生成の「予約チケット」を発行する（§20.5.1, §24）。
    /// `purpose`で機能を区別する（省略時はAI監督フィードバック向けの"coach_feedback"）。
    func createAdTicket(
        localSessionId: String,
        persona: String? = nil,
        purpose: String = "coach_feedback"
    ) async throws -> String {
        try await ensureAuthenticated()
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

        try await ensureAuthenticated()
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

        try await ensureAuthenticated()
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

    /// 指定したセッションに対して作られた二つ名を、新しい順に取得する（月ごとのまとめ用、技術実装仕様書 §27.3）
    func fetchNicknames(localSessionIds: [String]) async throws -> [NicknameRow] {
        guard let userId = currentUserId, !localSessionIds.isEmpty else { return [] }
        return try await client
            .from("player_nicknames")
            .select()
            .eq("user_id", value: userId)
            .in("local_session_id", values: localSessionIds)
            .order("created_at", ascending: false)
            .execute()
            .value
    }


    // MARK: - Encodable Row Types

    private struct UserRow: Encodable {
        let id: UUID
    }
}
