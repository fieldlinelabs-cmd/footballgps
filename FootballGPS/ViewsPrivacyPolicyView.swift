//
//  ViewsPrivacyPolicyView.swift
//  FootballGPS
//
//  アプリ内で読めるプライバシーポリシー（docs/公開準備.md §1・§2）。
//  Appleの審査では、App Store ConnectにURLを登録することと、アプリ内から読めることの両方が必要。
//  同じ文面を site/privacy.html にも置き、GitHub Pagesで公開する。
//  **文面を変えるときは site/privacy.html も同じように直し、制定日・改定日を更新する。**
//

import SwiftUI

/// 運営者・問い合わせ先・公開ページのURL。ポリシーとサポートページで使う値を1か所にまとめる
enum SupportInfo {
    static let operatorName = "Fieldline Labs"
    /// 問い合わせ先のメールアドレス（変えるときは site/ の2ページも同じく更新する）
    static let contactEmail: String? = "fieldline.labs@gmail.com"
    static let supportURL = URL(string: "https://fieldlinelabs-cmd.github.io/footballgps/")!
    static let privacyPolicyURL = URL(string: "https://fieldlinelabs-cmd.github.io/footballgps/privacy.html")!
    /// 制定日（改定したら改定日を足す）
    static let privacyPolicyDate = "2026年11月8日 制定、2026年11月10日 改定"
}

struct PrivacyPolicyView: View {
    private struct PolicySection: Identifiable {
        let title: String
        let paragraphs: [String]
        var id: String { title }
    }

    private let sections: [PolicySection] = [
        PolicySection(title: "1. はじめに", paragraphs: [
            "\(SupportInfo.operatorName)（以下「運営者」）は、FootballGPS（以下「本アプリ」）で扱う情報について、このプライバシーポリシーのとおりに取り扱います。",
            "本アプリで記録したデータは、利用者のiPhoneとApple Watchの中に保存します。運営者のサーバーに送ることはありません。",
        ]),
        PolicySection(title: "2. 端末の中に保存する情報", paragraphs: [
            "・プロフィール: 表示名、生年月日、性別、カテゴリー、チーム名、顔写真、チームのエンブレム（いずれも任意）。年齢と性別に合わせた基準で数値を評価するために使います。",
            "・計測データ: 計測中の位置（GPS）、速度、距離、心拍数、Apple Watchの動き（加速度）、セッションの日時。",
            "・フィールドの設定: 登録したフィールドの位置と向き。",
            "これらは端末の中だけに保存します。iPhoneのバックアップ（iCloudバックアップを含む）を利用している場合は、Appleの仕組みによってバックアップに含まれることがあります。GPSの記録をバックアップに含めるかは、設定画面で切り替えられます（初期設定はオフ）。",
        ]),
        PolicySection(title: "3. ヘルスケア（HealthKit）のデータ", paragraphs: [
            "本アプリは、Apple Watchでの計測中に心拍数などのヘルスケアのデータを読み取り、セッションの記録と分析だけに使います。",
            "ヘルスケアのデータを、広告やマーケティングに使うこと、第三者に提供・販売すること、運営者のサーバーに送ることはありません。",
        ]),
        PolicySection(title: "4. 位置情報", paragraphs: [
            "位置情報は、計測中の走った軌跡の記録と、フィールドの登録に使います。位置情報を端末の外に送ることはありません。",
        ]),
        PolicySection(title: "5. 広告（Google AdMob）", paragraphs: [
            "本アプリは、Google LLCが提供する広告配信サービス「Google AdMob」を利用しています。広告の表示と効果の測定、Googleによる分析のため、AdMobが次の情報を収集することがあります: 端末の情報（端末の種類、OSのバージョン、IPアドレス）、IPアドレスから推定したおおまかな地域、アプリの操作や広告の表示・タップの状況、アプリの動作状況（クラッシュや性能の情報）、広告識別子（IDFA）。",
            "広告識別子（IDFA）は、利用者がトラッキングを許可した場合に限って使われます。許可しない場合も、広告は表示されます。",
            "Googleによる情報の取り扱いは、Googleのプライバシーポリシーをご覧ください。",
        ]),
        PolicySection(title: "6. 通知", paragraphs: [
            "月間のまとめができたことをお知らせする通知は、端末の中で予約します。通知はiPhoneの設定でいつでもオフにできます。",
        ]),
        PolicySection(title: "7. 13歳未満の方の利用", paragraphs: [
            "13歳未満の方は、保護者の方の同意を得てからご利用ください。",
        ]),
        PolicySection(title: "8. データの削除", paragraphs: [
            "セッションは、アプリの中から1件ずつ削除できます。",
            "本アプリを削除すると、端末の中に保存したデータはすべて削除されます。iPhoneのバックアップに含まれているデータは、そのバックアップを削除すると消えます。",
        ]),
        PolicySection(title: "9. このポリシーの変更", paragraphs: [
            "機能の追加などに合わせて、このポリシーを変更することがあります。変更した場合は、このページとアプリの中でお知らせします。",
        ]),
    ]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.paragraphs, id: \.self) { paragraph in
                        Text(paragraph)
                            .font(.subheadline)
                    }
                    if section.title.hasPrefix("5.") {
                        Link("Googleのプライバシーポリシー", destination: URL(string: "https://policies.google.com/privacy")!)
                            .font(.subheadline)
                        Link("Googleのサービスを使うアプリでのデータの使われ方", destination: URL(string: "https://policies.google.com/technologies/partner-sites")!)
                            .font(.subheadline)
                    }
                } header: {
                    Text(section.title)
                }
            }

            Section {
                Text(SupportInfo.operatorName)
                    .font(.subheadline)
                if let email = SupportInfo.contactEmail, let url = URL(string: "mailto:\(email)") {
                    Link(email, destination: url)
                        .font(.subheadline)
                }
                Link("サポートページ", destination: SupportInfo.supportURL)
                    .font(.subheadline)
            } header: {
                Text("10. お問い合わせ")
            } footer: {
                Text(SupportInfo.privacyPolicyDate)
            }
        }
        .navigationTitle("プライバシーポリシー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
