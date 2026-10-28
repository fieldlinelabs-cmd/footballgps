//
//  ViewsNicknameGeneratorView.swift
//  FootballGPS
//
//  「二つ名」生成機能（§24）。プレイヤーデータ画面から呼び出すシート形式の
//  ウィザード（セッション選択 → 広告視聴 → 生成結果）。AI監督フィードバック
//  （AICoachFeedbackSection, ViewsSessionDetailView.swift）と同じチケット・
//  fail-openの制御フローを踏襲する。
//

import SwiftUI

struct NicknameGeneratorView: View {
    /// 生成が確定した二つ名。呼び出し元（PlayerDataView）でヘッダーの称号表示を更新する
    let onDecided: (NicknameResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var dataManager = SessionDataManager.shared
    @ObservedObject private var adManager = RewardedAdManager.shared

    private enum Phase {
        case pickSession
        case generating
        case result(NicknameResult)
    }

    @State private var phase: Phase = .pickSession
    @State private var selectedSession: TrainingSession?
    @State private var errorMessage: String?
    @State private var showNoAdNotice = false

    private var sortedSessions: [TrainingSession] {
        dataManager.sessions.sorted { $0.date > $1.date }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .pickSession:
                    sessionPicker
                case .generating:
                    generatingView
                case .result(let result):
                    resultView(result)
                }
            }
            .navigationTitle("二つ名をつける")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear { adManager.preload() }
    }

    private var sessionPicker: some View {
        List {
            Section {
                Text("元になるセッションを選んでください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(sortedSessions) { session in
                Button {
                    selectedSession = session
                    Task { await generate(for: session) }
                } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var generatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("広告を再生しています…")
                .font(.caption)
                .foregroundStyle(.secondary)

            if showNoAdNotice {
                Text("広告が表示できなかったため、そのまま生成します")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("セッション選択に戻る") { phase = .pickSession }
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func resultView(_ result: NicknameResult) -> some View {
        VStack(spacing: 20) {
            Spacer()

            Text(result.nickname)
                .font(.system(size: 34, weight: .heavy))
                .multilineTextAlignment(.center)

            Text(result.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button("この二つ名にする") {
                    onDecided(result)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button("もう一度つけ直す") {
                    guard let selectedSession else { return }
                    Task { await generate(for: selectedSession) }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)

            Text("AIによる創作コメントです")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical)
    }

    // MARK: - Actions

    private func generate(for session: TrainingSession) async {
        phase = .generating
        errorMessage = nil
        showNoAdNotice = false

        guard let viewController = UIViewController.currentForPresentation else {
            errorMessage = "画面の準備ができていません。もう一度お試しください。"
            return
        }
        guard let gpsData = dataManager.getGPSData(for: session.id) else {
            errorMessage = "GPSデータが見つかりませんでした。"
            return
        }

        do {
            let ticketId = try await SupabaseManager.shared.createAdTicket(
                localSessionId: session.id,
                purpose: "nickname"
            )

            let presentResult = await adManager.presentAndWaitForReward(
                ticketId: ticketId,
                from: viewController
            )

            switch presentResult {
            case .rewarded:
                try await fetchWithFreeRetry(ticketId: ticketId, session: session, gpsData: gpsData)
            case .notRewarded:
                phase = .pickSession // 広告を最後まで見なかったので何もしない
            case .noFill:
                showNoAdNotice = true
                try await fetchWithFreeRetry(ticketId: nil, session: session, gpsData: gpsData)
            }
        } catch let error as AICoachFeedbackError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = "生成中にエラーが発生しました。もう一度お試しください。"
        }
    }

    /// 広告視聴後にAPI呼び出しが失敗した場合、同じticketで無料の1回だけ即時リトライする（§20.6と同様）
    private func fetchWithFreeRetry(ticketId: String?, session: TrainingSession, gpsData: GPSData) async throws {
        do {
            try await fetchAndApply(ticketId: ticketId, session: session, gpsData: gpsData)
        } catch {
            try await fetchAndApply(ticketId: ticketId, session: session, gpsData: gpsData)
        }
    }

    private func fetchAndApply(ticketId: String?, session: TrainingSession, gpsData: GPSData) async throws {
        let summary = buildSummary(session: session, gpsData: gpsData)
        let result = try await SupabaseManager.shared.fetchNickname(
            ticketId: ticketId,
            localSessionId: session.id,
            sessionSummary: summary
        )
        phase = .result(result)
    }

    /// AI監督フィードバックと同じデータ（buildFeedbackSummaryText）を、選択したセッションについて
    /// 都度計算する。ViewsSessionDetailView.swift の statisticsView(field:) と同じ手順。
    private func buildSummary(session: TrainingSession, gpsData: GPSData) -> String {
        let sprintSegments = SessionDataManager.computeSprintSegments(gpsData.points)
        let timeSeries = SessionDataManager.computeTimeSeries(gpsPoints: gpsData.points)
        let staminaDrop = SessionDataManager.computeStaminaDropRate(buckets: timeSeries)
        let sprintCnt = sprintSegments.isEmpty ? (session.sprintCount ?? 0) : sprintSegments.count

        let hrIntensity: (highIntensityRatio: Double, highIntensitySprintCount: Int)? =
            UserProfileManager.shared.age.flatMap {
                SessionDataManager.computeHeartRateIntensity(gpsPoints: gpsData.points, age: $0)
            }

        let radar = SessionDataManager.computePlayerRadar(
            totalDistance: session.totalDistance,
            duration: session.duration,
            sprintCount: sprintCnt,
            agilityTurnCount: session.agilityTurnCount,
            staminaDrop: staminaDrop,
            hrIntensityRatio: hrIntensity?.highIntensityRatio,
            maxSpeed: session.maxSpeed
        )

        let thirdRatios: (defensive: Double, middle: Double, attacking: Double)
        if let fieldId = session.fieldId, let field = FieldManager.shared.getField(by: fieldId) {
            thirdRatios = SessionDataManager.computeThirdRatios(
                gpsData: gpsData, field: field, isFlipped: session.isFlipped
            )
        } else {
            thirdRatios = (0, 0, 0)
        }

        return SessionDataManager.buildFeedbackSummaryText(
            session: session,
            thirdRatios: thirdRatios,
            staminaDropRate: staminaDrop,
            radar: radar,
            sprintCount: sprintCnt
        )
    }
}
