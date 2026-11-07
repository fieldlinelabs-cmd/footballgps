//
//  ViewsSprintThresholdHelpView.swift
//  FootballGPS
//
//  ヘルプ「スプリントの基準」（技術実装仕様書 §13.4.A）。
//  数値は SessionDataManager.sprintThreshold から表示し、表と計算がずれないようにする。
//

import SwiftUI

struct SprintThresholdHelpView: View {
    @ObservedObject private var profileManager = UserProfileManager.shared

    private struct AgeBand: Identifiable {
        let label: String
        let ages: ClosedRange<Int>
        var id: String { label }
        /// 基準を引くときの代表の年齢
        var representativeAge: Int { ages.lowerBound }
    }

    private let bands: [AgeBand] = [
        AgeBand(label: "11歳以下", ages: 0...11),
        AgeBand(label: "12歳", ages: 12...12),
        AgeBand(label: "13歳", ages: 13...13),
        AgeBand(label: "14〜15歳", ages: 14...15),
        AgeBand(label: "16〜39歳", ages: 16...39),
        AgeBand(label: "40代", ages: 40...49),
        AgeBand(label: "50代", ages: 50...59),
        AgeBand(label: "60代", ages: 60...69),
        AgeBand(label: "70歳以上", ages: 70...200),
    ]

    /// 年齢未設定のときは計算と同じく25歳として扱う
    private var userAge: Int { profileManager.age ?? 25 }
    private var userIsFemale: Bool { profileManager.profile.gender == .female }

    private func kmh(age: Int, female: Bool) -> String {
        let value = SessionDataManager.sprintThreshold(age: age, gender: female ? .female : .male) * 3.6
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }

    var body: some View {
        List {
            Section {
                Text("年齢・性別ごとに決めた速さ以上で、1秒以上走ると1回と数えます。16〜39歳はプロと同じ基準です（男子 時速25km＝Jリーグ・FIFA、女子 時速23km＝FIFA女子ワールドカップ）。")
                    .font(.subheadline)
            } header: {
                Text("スプリントの数え方")
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("年齢")
                        Text("男子").gridColumnAlignment(.trailing)
                        Text("女子").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                    ForEach(bands) { band in
                        let isUserBand = band.ages.contains(userAge)
                        GridRow {
                            HStack(spacing: 4) {
                                Text(band.label)
                                if isUserBand {
                                    Text("あなた")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.accentColor.opacity(0.15))
                                        .foregroundStyle(Color.accentColor)
                                        .cornerRadius(4)
                                }
                            }
                            thresholdText(age: band.representativeAge, female: false,
                                          highlighted: isUserBand && !userIsFemale)
                            thresholdText(age: band.representativeAge, female: true,
                                          highlighted: isUserBand && userIsFemale)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.vertical, 4)

                if profileManager.age == nil || profileManager.profile.gender == nil {
                    Text("生年月日や性別が未設定のときは、16〜39歳の男子の基準（時速25km）で数えます。設定のプロフィールから登録できます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("年代ごとの基準（時速）")
            }

            Section {
                helpRow(title: "16〜39歳", text: "プロの試合と同じ基準です。")
                helpRow(title: "15歳以下", text: "育成年代の研究で調べた、その年代の試合での最高速度をもとにしています。")
                helpRow(title: "40歳以上", text: "地域のマスターズ陸上大会の100mの記録（真ん中くらいの選手）をもとにしています。")
                Text("どの年代も、その年代の速さに対してプロと同じくらいの難しさになるようにしています。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("基準の決め方")
            }

            Section {
                Text("Jリーグでは、サイドの選手は90分で約20回、ボランチの選手は約8回のスプリントを記録しています（2026/27シーズン）。")
                Text("Apple Watchは約1秒ごとに位置を測るため、短いダッシュは実際より低めに出ることがあります。同じ基準でも、プロの計測より回数は少なめになります。")
                    .foregroundStyle(.secondary)
            } header: {
                Text("参考")
            }
            .font(.subheadline)
        }
        .navigationTitle("スプリントの基準")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func thresholdText(age: Int, female: Bool, highlighted: Bool) -> some View {
        Text(kmh(age: age, female: female) + "km")
            .monospacedDigit()
            .fontWeight(highlighted ? .bold : .regular)
            .foregroundStyle(highlighted ? Color.accentColor : Color.primary)
            .gridColumnAlignment(.trailing)
    }

    private func helpRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(text).font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
