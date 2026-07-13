//
//  RewardedAdManager.swift
//  FootballGPS
//
//  AI監督フィードバック機能（§20.6）のリワード広告管理。
//  広告視聴の真正性はAdMob Server-Side Verification（SSV, §20.5.2）でサーバー側が
//  検証するため、ここでは「ユーザーが広告視聴を完了したか」をUI表示のために追うだけで、
//  実際の生成許可はEdge Function側のticket検証が担う。

import Combine
import GoogleMobileAds
import UIKit

@MainActor
final class RewardedAdManager: NSObject, ObservableObject {
    static let shared = RewardedAdManager()

    // AI監督フィードバック機能（§20）用のリワード広告ユニットID
    private let adUnitID = "ca-app-pub-4525766212952142/9279453167"

    /// 事前ロード完了しているか（UIの状態表示用）
    @Published private(set) var isAdReady = false

    private var rewardedAd: GADRewardedAd?
    private var loadTask: Task<Void, Never>?
    private var presentationDelegate: RewardedAdPresentationDelegate?

    enum PresentResult {
        /// 広告を最後まで視聴し、reward獲得コールバックが発火した
        case rewarded
        /// 広告は表示されたが、最後まで視聴されなかった
        case notRewarded
        /// 事前ロードが間に合わず（3秒待っても未ロード）、広告を表示できなかった
        case noFill
    }

    /// `SessionDetailView` 表示時にバックグラウンドで事前ロードする（§20.6 手順1）
    func preload() {
        guard rewardedAd == nil, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.load()
            self?.loadTask = nil
        }
    }

    private func load() async {
        do {
            rewardedAd = try await GADRewardedAd.load(withAdUnitID: adUnitID, request: GADRequest())
            isAdReady = true
            print("🎬 リワード広告 読み込み成功")
        } catch {
            rewardedAd = nil
            isAdReady = false
            let nsError = error as NSError
            print("🎬 リワード広告 読み込み失敗: domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription) userInfo=\(nsError.userInfo)")
        }
    }

    /// 広告を表示し、視聴完了まで待つ（§20.6 手順3〜4）。
    /// `ticketId` は `GADServerSideVerificationOptions.customRewardString` としてAdMobに渡され、
    /// AdMobのSSV通知でサーバー側（`ad-reward-callback`）に転送される。
    func presentAndWaitForReward(
        ticketId: String,
        from viewController: UIViewController
    ) async -> PresentResult {
        if rewardedAd == nil {
            await waitForLoadWithTimeout(seconds: 3)
        }
        guard let ad = rewardedAd else {
            return .noFill
        }

        let options = GADServerSideVerificationOptions()
        options.customRewardString = ticketId
        ad.serverSideVerificationOptions = options

        // 表示後は再利用できないため参照を外し、次回のために早めに再ロードしておく
        rewardedAd = nil
        isAdReady = false
        preload()

        return await withCheckedContinuation { (continuation: CheckedContinuation<PresentResult, Never>) in
            var didEarnReward = false
            let delegate = RewardedAdPresentationDelegate(
                onDismissOrFail: {
                    continuation.resume(returning: didEarnReward ? .rewarded : .notRewarded)
                }
            )
            presentationDelegate = delegate
            ad.fullScreenContentDelegate = delegate
            ad.present(fromRootViewController: viewController) {
                didEarnReward = true
            }
        }
    }

    private func waitForLoadWithTimeout(seconds: TimeInterval) async {
        let deadline = Date().addingTimeInterval(seconds)
        while rewardedAd == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

/// 広告のフルスクリーン表示イベントを、Swift Concurrencyの継続に橋渡しするだけの薄いdelegate
private final class RewardedAdPresentationDelegate: NSObject, GADFullScreenContentDelegate {
    private let onDismissOrFail: () -> Void

    init(onDismissOrFail: @escaping () -> Void) {
        self.onDismissOrFail = onDismissOrFail
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        onDismissOrFail()
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismissOrFail()
    }
}

extension UIViewController {
    /// 現在アクティブなウィンドウのルートビューコントローラを取得する（広告表示用）
    static var currentForPresentation: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
