//
//  AdConfiguration.swift
//  FootballGPS
//
//  広告ユニットIDと、広告の要求に付ける設定を1か所にまとめる（docs/広告仕様書.md §10.2・§10.3）。
//  - TestFlightとXcodeから入れたビルドではGoogleのテスト用IDを使い、App Store版だけ本番IDを使う
//  - 13歳未満と分かっている利用者の広告には、子ども向けのタグと全年齢（G）の制限を付ける
//

import GoogleMobileAds
import StoreKit

/// アプリで使う広告ユニット。AI用のリワード広告（RewardedAdManager）は、広告視聴の確認（SSV）が
/// 本番の広告ユニットでしか動かないため対象外（AI機能を戻すときに扱いを決める、広告仕様書 §10.2）
enum AdUnit: CaseIterable {
    case native
    case interstitial

    /// Google公式のテスト用ID
    var testID: String {
        switch self {
        case .native: return "ca-app-pub-3940256099942544/3986624511"
        case .interstitial: return "ca-app-pub-3940256099942544/4411468910"
        }
    }

    /// 本番ID。AdMobで広告ユニットを作成したらここに入れる（docs/公開準備.md §2）。
    /// nil の間は、App Store版では広告を出さない
    var productionID: String? {
        switch self {
        case .native: return nil
        case .interstitial: return nil
        }
    }
}

/// アプリの配布元の環境
enum DistributionEnvironment: Equatable {
    case appStore
    case testFlight
    case xcode
    /// 判定に失敗した
    case unknown
}

@MainActor
enum AdConfiguration {
    #if DEBUG
    static let isDebugBuild = true
    #else
    static let isDebugBuild = false
    #endif

    /// 起動時に判定した配布元。判定が終わるまでは nil
    private(set) static var environment: DistributionEnvironment?

    // MARK: - 広告ユニットID（§10.2）

    /// その広告に使う広告ユニットID。nil なら広告を読み込まない
    static func adUnitID(for unit: AdUnit) -> String? {
        switch adSource(isDebugBuild: isDebugBuild, environment: environment) {
        case .test: return unit.testID
        case .production: return unit.productionID
        case .undetermined: return nil
        }
    }

    enum AdSource: Equatable {
        case test
        case production
        /// 配布元を判定中。App Store版にテスト広告を出さないよう、判定が終わるまで広告を読み込まない
        case undetermined
    }

    /// 本番の広告を使うのはApp Store版だけ。判定に失敗したときは、本番の広告がテスターに出るより
    /// 害が小さいテスト広告を使う（§10.2「判定できないとき」）
    nonisolated static func adSource(isDebugBuild: Bool, environment: DistributionEnvironment?) -> AdSource {
        if isDebugBuild { return .test }
        guard let environment else { return .undetermined }
        return environment == .appStore ? .production : .test
    }

    /// 起動時に1回呼び、配布元を判定する
    static func resolveEnvironment() async {
        guard environment == nil else { return }
        do {
            let result = try await AppTransaction.shared
            let transaction: AppTransaction
            switch result {
            case .verified(let value): transaction = value
            case .unverified(let value, _): transaction = value
            }
            environment = distributionEnvironment(from: transaction.environment)
        } catch {
            environment = .unknown
            print("🎬 配布元の判定に失敗: \(error.localizedDescription)（テスト広告を使う）")
        }
        print("🎬 配布元: \(String(describing: environment))、広告: \(adSource(isDebugBuild: isDebugBuild, environment: environment))")
    }

    nonisolated static func distributionEnvironment(from storeEnvironment: AppStore.Environment) -> DistributionEnvironment {
        switch storeEnvironment {
        case .production: return .appStore
        case .sandbox: return .testFlight
        case .xcode: return .xcode
        default: return .unknown
        }
    }

    // MARK: - 子ども向けのタグ（§10.3）

    /// 13歳未満と分かっているか。生年月日が未入力（age が nil）なら付けない
    nonisolated static func isChildDirected(age: Int?) -> Bool {
        guard let age else { return false }
        return age < 13
    }

    /// 今の年齢に合わせて、すべての広告の要求に付く設定を更新する。
    /// 年齢は保存せず毎回生年月日から計算するため、起動時・前面に戻ったとき・生年月日を変えたときに呼ぶ
    static func applyAudienceSettings() {
        let isChild = isChildDirected(age: UserProfileManager.shared.age)
        let configuration = GADMobileAds.sharedInstance().requestConfiguration
        configuration.tagForChildDirectedTreatment = isChild ? true : nil
        configuration.maxAdContentRating = isChild ? .general : nil
    }
}
