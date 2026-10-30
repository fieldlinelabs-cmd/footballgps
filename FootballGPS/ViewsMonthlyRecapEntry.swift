//
//  ViewsMonthlyRecapEntry.swift
//  FootballGPS
//
//  月ごとのまとめの入口（Statsタブ・Sessionsタブ）と通知（技術実装仕様書 §27.5）
//

import SwiftUI
import UserNotifications

/// まとめを見た月の記録。最後に見た月より古い月は見たものとみなす
enum MonthlyRecapSeen {
    static let key = "monthlyRecap.lastViewedMonth"

    static func isViewed(_ month: RecapMonth) -> Bool {
        guard let last = UserDefaults.standard.string(forKey: key) else { return false }
        return month.id <= last  // "yyyy-MM" は文字列の順で比べられる
    }

    static func markViewed(_ month: RecapMonth) {
        if !isViewed(month) {
            UserDefaults.standard.set(month.id, forKey: key)
        }
    }
}

/// まとめのストーリーを開く（月を渡すと、その場で集計して表示する）
private struct MonthlyRecapPresenter: ViewModifier {
    @Binding var month: RecapMonth?
    @ObservedObject private var dataManager = SessionDataManager.shared

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $month) { month in
            if let recap = MonthlyRecapEngine.recap(
                for: month,
                sessions: dataManager.sessions,
                playerCategory: UserProfileManager.shared.profile.playerCategory
            ) {
                MonthlyRecapStoryView(recap: recap)
                    .onAppear { MonthlyRecapSeen.markViewed(month) }
            }
        }
    }
}

extension View {
    func monthlyRecapPresenter(month: Binding<RecapMonth?>) -> some View {
        modifier(MonthlyRecapPresenter(month: month))
    }
}

// MARK: - Statsタブ

struct MonthlyRecapEntrySection: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @State private var presented: RecapMonth?

    private var months: [RecapMonth] { MonthlyRecapEngine.availableMonths(sessions: dataManager.sessions) }

    var body: some View {
        if let latest = months.first {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    presented = latest
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(latest.title)のまとめを見る")
                                .font(.headline)
                            Text("1か月のサッカーをストーリーで振り返る")
                                .font(.caption)
                                .opacity(0.85)
                        }
                        Spacer()
                        Image(systemName: "play.fill")
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.40, blue: 0.22), Color(red: 0.02, green: 0.15, blue: 0.10)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)

                if months.count > 1 {
                    NavigationLink {
                        MonthlyRecapListView(months: months)
                    } label: {
                        Text("過去のまとめ")
                            .font(.subheadline)
                    }
                }
            }
            .padding(.horizontal)
            .monthlyRecapPresenter(month: $presented)
        }
    }
}

struct MonthlyRecapListView: View {
    let months: [RecapMonth]
    @State private var presented: RecapMonth?

    var body: some View {
        List(months) { month in
            Button {
                presented = month
            } label: {
                HStack {
                    Text(month.fullTitle)
                    Spacer()
                    Image(systemName: "play.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("月ごとのまとめ")
        .navigationBarTitleDisplayMode(.inline)
        .monthlyRecapPresenter(month: $presented)
    }
}

// MARK: - Sessionsタブ（まだ見ていない最新の月があるときだけ）

/// まだ見ていない最新の月のカード。まとめを開くと「見た」と記録されてカードがリストから消えるため、
/// 全画面の表示はこのカードではなく、リストを持つ画面（SessionsListView）に付ける。
/// カードに付けると、開いた瞬間にカードと一緒に表示も消えてしまう
struct MonthlyRecapUnseenCard: View {
    let month: RecapMonth
    let onOpen: (RecapMonth) -> Void

    var body: some View {
        Button {
            onOpen(month)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(month.title)のまとめができました")
                        .font(.subheadline.bold())
                    Text("タップして振り返る")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 通知（ローカル通知）

enum MonthlyRecapNotifier {
    /// 今月の対象のセッションが3回に達していれば、翌月1日の9時に通知を予約する。
    /// 通知の許可はこのとき初めて求める。同じ月の予約は識別子で上書きされる
    @MainActor
    static func scheduleIfNeeded(sessions: [TrainingSession], now: Date = Date()) {
        let current = RecapMonth(date: now)
        guard MonthlyRecapEngine.eligibleSessions(in: current, from: sessions).count >= MonthlyRecapEngine.minimumSessions else { return }

        let center = UNUserNotificationCenter.current()
        Task {
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return }
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "\(current.title)のまとめができました"
            content.body = "1か月のサッカーを振り返りましょう"
            content.sound = .default

            var trigger = DateComponents()
            trigger.year = current.next.year
            trigger.month = current.next.month
            trigger.day = 1
            trigger.hour = 9
            let request = UNNotificationRequest(
                identifier: "monthlyRecap-\(current.id)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: trigger, repeats: false)
            )
            try? await center.add(request)
        }
    }
}
