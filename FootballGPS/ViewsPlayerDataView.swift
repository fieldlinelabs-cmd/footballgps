//
//  ViewsPlayerDataView.swift
//  FootballGPS
//
//  「プレイヤーデータ」画面（§22）。レベル・直近5回平均との比較カード・
//  バッジ一覧を表示する。計算は PlayerDataEngine に集約し、このファイルは
//  表示のみを担当する。

import SwiftUI

struct PlayerDataView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @ObservedObject private var profileManager = UserProfileManager.shared

    @State private var latestNickname: NicknameRow?
    @State private var showNicknameGenerator = false
    @State private var showNicknameReason = false

    private var sessions: [TrainingSession] { dataManager.sessions }

    private var totalXP: Int { PlayerDataEngine.totalXP(sessions: sessions) }
    private var level: Int { PlayerDataEngine.level(forXP: totalXP) }
    private var xpIntoLevel: Int { PlayerDataEngine.xpIntoCurrentLevel(totalXP) }
    private var xpToNext: Int { PlayerDataEngine.xpToNextLevel(totalXP) }

    private var comparison: PlayerDataEngine.SessionComparison? {
        PlayerDataEngine.compareToRecentAverage(sessions: sessions)
    }

    private var sections: [PlayerDataEngine.BadgeSection] {
        PlayerDataEngine.allSections(sessions: sessions, playerCategory: profileManager.profile.playerCategory)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headerCard
                    nicknameButton
                    comparisonCard
                    radarCard
                    ForEach(sections) { section in
                        badgeSectionView(section)
                    }
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Player Data")
            .task { await loadLatestNickname() }
            .sheet(isPresented: $showNicknameGenerator) {
                NicknameGeneratorView { result in
                    latestNickname = NicknameRow(
                        id: UUID(), nickname: result.nickname, reason: result.reason, createdAt: Date()
                    )
                }
            }
        }
    }

    private func loadLatestNickname() async {
        latestNickname = try? await SupabaseManager.shared.fetchLatestNickname()
    }

    // MARK: - ヘッダー（所属チーム・アバター・レベル）

    private var hasTeamInfo: Bool {
        profileManager.profile.teamEmblemImageData != nil
            || !(profileManager.profile.teamName ?? "").isEmpty
    }

    private var headerCard: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 14) {
                if hasTeamInfo {
                    Text(profileManager.profile.teamName?.isEmpty == false ? profileManager.profile.teamName! : "所属チーム未設定")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .padding(.trailing, 90)
                }

                HStack(spacing: 20) {
                    avatarView
                    VStack(alignment: .leading, spacing: 6) {
                        if let latestNickname {
                            Button {
                                showNicknameReason = true
                            } label: {
                                Text("「\(latestNickname.nickname)」")
                                    .font(.caption.bold())
                                    .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                        Text(profileManager.profile.displayName.isEmpty ? "名前未設定" : profileManager.profile.displayName)
                            .font(.headline)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("Lv.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(level)")
                                .font(.largeTitle.bold())
                        }
                        ProgressView(value: Double(xpIntoLevel), total: 1000)
                            .tint(.accentColor)
                        Text("次のレベルまで \(xpToNext) XP")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if hasTeamInfo {
                teamEmblemView
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
        .alert(
            latestNickname.map { "「\($0.nickname)」" } ?? "",
            isPresented: $showNicknameReason
        ) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(latestNickname?.reason ?? "")
        }
    }

    private var nicknameButton: some View {
        Button {
            showNicknameGenerator = true
        } label: {
            Label(latestNickname == nil ? "二つ名をつける" : "二つ名をつけ直す", systemImage: "sparkles")
                .font(.caption2)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)
    }

    private var avatarView: some View {
        Group {
            if let data = profileManager.profile.avatarImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 128, height: 128)
        .clipShape(Circle())
    }

    @ViewBuilder
    private var teamEmblemView: some View {
        Group {
            if let data = profileManager.profile.teamEmblemImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 78, height: 78)
        .clipShape(Circle())
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }

    // MARK: - 比較カード

    @ViewBuilder
    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今回 vs 直近5回平均")
                .font(.subheadline.bold())

            if let comparison {
                HStack {
                    VStack(spacing: 2) {
                        Text(formatDistance(comparison.currentDistance))
                            .font(.title3.bold())
                        Text(formatDuration(comparison.currentDuration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("今回")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(String(format: "%+.0f%%", comparison.percentDiff))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(comparison.percentDiff >= 0 ? Color.green : Color.orange)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                    Spacer()
                    VStack(spacing: 2) {
                        Text(formatDistance(comparison.recentAverageDistance))
                            .font(.title3.bold())
                        Text(formatDuration(comparison.recentAverageDuration))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("直近5回平均")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("セッションが6件以上貯まると表示されます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }

    private func formatDistance(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.1fkm", meters / 1000) : String(format: "%.0fm", meters)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        if hours > 0 {
            return "\(hours)時間\(minutes)分"
        } else {
            return "\(minutes)分"
        }
    }

    // MARK: - レーダーチャート（直近5回平均・自己ベスト・直前のセッション）

    @ViewBuilder
    private var radarCard: some View {
        if let comparison = PlayerDataEngine.radarComparison(sessions: sessions) {
            VStack(spacing: 12) {
                Text("直近5回平均・自己ベスト・直前のセッション")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                RadarChartView(
                    values: comparison.recentAverage,
                    labels: PlayerDataEngine.radarAxisLabels,
                    valuesColor: .green,
                    referenceA: comparison.latestSession,
                    personalAvg: comparison.personalBest,
                    personalAvgColor: .orange
                )
                .frame(height: 220)

                HStack(spacing: 16) {
                    RadarLegendItem(color: .green, dashed: false, label: "直近5回平均")
                    RadarLegendItem(color: .orange, dashed: false, label: "自己ベスト")
                    RadarLegendItem(color: .gray, dashed: true, label: "直前のセッション")
                }
                .font(.caption2)
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }

    // MARK: - バッジセクション

    private func badgeSectionView(_ section: PlayerDataEngine.BadgeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title)
                .font(.subheadline.bold())
                .padding(.horizontal)

            if section.badges.isEmpty {
                Text("まだありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(section.badges) { badge in
                        BadgeCell(badge: badge)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct BadgeCell: View {
    let badge: PlayerDataEngine.BadgeProgress

    var body: some View {
        VStack(spacing: 6) {
            iconView

            Text(displayName)
                .font(.caption2.bold())
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(badge.unlocked ? .primary : .secondary)

            if let reason = badge.unavailableReason {
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if badge.isHidden && !badge.unlocked {
                Text("未発見")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let next = badge.nextThreshold {
                ProgressView(value: Double(badge.currentValue), total: Double(next))
                    .tint(.secondary)
                Text("\(badge.currentValue) / \(next)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if badge.unlocked {
                Text(badge.tier?.displayName ?? "達成済み")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(14)
    }

    private var displayName: String {
        badge.isHidden && !badge.unlocked ? "？？？" : badge.name
    }

    @ViewBuilder
    private var iconView: some View {
        ZStack {
            Circle()
                .fill(backgroundStyle)
                .frame(width: 44, height: 44)

            if badge.isHidden && !badge.unlocked {
                Text("？")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: badge.sfSymbol)
                    .symbolRenderingMode(badge.unlocked ? .palette : .monochrome)
                    .foregroundStyle(iconForeground.0, iconForeground.1)
                    .font(.system(size: 18, weight: .semibold))
            }

            if !badge.unlocked && badge.unavailableReason == nil && !badge.isHidden {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(Circle().fill(Color.gray))
                    .offset(x: 16, y: 16)
            }
        }
    }

    private var backgroundStyle: AnyShapeStyle {
        guard badge.unlocked else {
            return AnyShapeStyle(Color(.systemGray5))
        }
        switch badge.tier {
        case .start, .bronze:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.79, green: 0.55, blue: 0.33), Color(red: 0.55, green: 0.35, blue: 0.18)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .silver:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(white: 0.85), Color(white: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .gold:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.96, green: 0.78, blue: 0.35), Color(red: 0.72, green: 0.52, blue: 0.13)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case .platinum:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.9, green: 0.98, blue: 0.98), Color(red: 0.6, green: 0.85, blue: 0.87)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
        case nil:
            return AnyShapeStyle(Color.accentColor.opacity(0.18))
        }
    }

    private var iconForeground: (Color, Color) {
        badge.tier == nil ? (Color.accentColor, Color.accentColor) : (Color.white, Color.white.opacity(0.7))
    }
}

#Preview {
    PlayerDataView()
}
