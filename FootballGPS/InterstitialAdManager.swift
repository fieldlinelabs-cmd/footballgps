//
//  InterstitialAdManager.swift
//  FootballGPS
//
//  セッション詳細を見終わった後のインタースティシャル広告（docs/広告仕様書.md §4.2・§4.2.1）。
//  詳細画面から離れたとき（一覧へ戻る・別タブへ切り替え）に、各セッションで1回だけ表示する。
//  - 滞在が10秒未満なら出さない
//  - 実際に表示できたときに初めて「表示済み」にする（no-fillや取り逃しは次回に持ち越す）
//  - 同じ閲覧中にAI監督フィードバックのリワード広告を見た場合は表示済みとみなす
//

import Combine
import GoogleMobileAds
import UIKit

@MainActor
final class InterstitialAdManager: NSObject, ObservableObject {
    static let shared = InterstitialAdManager()

    // Debugビルドは実機で動作確認できるようGoogle公式のテスト用ID。
    // 本番IDはAdMobでインタースティシャルの広告ユニットを作成後にここへ設定する（未設定の間は何もしない）。
    #if DEBUG
    private let adUnitID: String? = "ca-app-pub-3940256099942544/4411468910"
    #else
    private let adUnitID: String? = nil
    #endif

    private let minimumDwellSeconds: TimeInterval = 10
    // 戻る操作の画面遷移が終わってから表示するための待ち時間
    private let presentDelaySeconds: TimeInterval = 0.5
    private let shownSessionIdsKey = "interstitialShownSessionIds"

    private var interstitialAd: GADInterstitialAd?
    private var loadTask: Task<Void, Never>?
    private var presentationDelegate: InterstitialAdPresentationDelegate?

    // 1回の閲覧（詳細画面を開いてから離れるまで）の状態
    private var visitSessionId: String?
    private var visitStartedAt: Date?
    private var isVisitActive = false

    // MARK: - 詳細画面のライフサイクル

    func detailDidAppear(sessionId: String) {
        guard adUnitID != nil else { return }
        // リワード広告の全画面表示から戻った場合など、同じ閲覧の続きなら開始時刻を保つ
        if visitSessionId != sessionId || visitStartedAt == nil {
            visitSessionId = sessionId
            visitStartedAt = Date()
        }
        isVisitActive = true
        if !hasShown(sessionId: sessionId) {
            preload()
        }
    }

    func detailDidDisappear(sessionId: String) {
        guard adUnitID != nil, visitSessionId == sessionId else { return }
        isVisitActive = false
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.presentDelaySeconds * 1_000_000_000))
            self.presentIfStillAway(sessionId: sessionId)
        }
    }

    /// AI監督フィードバックのリワード広告が表示された場合に呼ぶ。1回の閲覧で広告を2回見せないため、表示済みとみなす
    func markRewardedAdWatched(sessionId: String) {
        markShown(sessionId: sessionId)
    }

    // MARK: - 表示

    private func presentIfStillAway(sessionId: String) {
        // 待っている間に詳細画面へ戻ってきた（全画面のモーダルから戻った等）なら、まだ見ている途中
        guard visitSessionId == sessionId, !isVisitActive, let startedAt = visitStartedAt else { return }
        // 確認が終わったら、表示したかどうかに関係なく閲覧を終える
        visitSessionId = nil
        visitStartedAt = nil

        guard Date().timeIntervalSince(startedAt) >= minimumDwellSeconds,
              !hasShown(sessionId: sessionId),
              UIApplication.shared.applicationState == .active,
              let viewController = UIViewController.currentForPresentation,
              viewController.presentedViewController == nil,
              let ad = interstitialAd else {
            return
        }

        interstitialAd = nil
        let delegate = InterstitialAdPresentationDelegate(
            onWillPresent: { [weak self] in
                self?.markShown(sessionId: sessionId)
                print("🎬 インタースティシャル広告 表示: session=\(sessionId)")
            },
            onDismissOrFail: { [weak self] in
                self?.presentationDelegate = nil
                self?.preload()
            }
        )
        presentationDelegate = delegate
        ad.fullScreenContentDelegate = delegate
        ad.present(fromRootViewController: viewController)
    }

    // MARK: - 読み込み

    private func preload() {
        guard let adUnitID, interstitialAd == nil, loadTask == nil else { return }
        loadTask = Task { [weak self] in
            await self?.load(adUnitID: adUnitID)
            self?.loadTask = nil
        }
    }

    private func load(adUnitID: String) async {
        do {
            interstitialAd = try await GADInterstitialAd.load(withAdUnitID: adUnitID, request: GADRequest())
            print("🎬 インタースティシャル広告 読み込み成功")
        } catch {
            interstitialAd = nil
            let nsError = error as NSError
            print("🎬 インタースティシャル広告 読み込み失敗: domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
        }
    }

    // MARK: - 表示済みの記録

    private func hasShown(sessionId: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: shownSessionIdsKey) ?? []).contains(sessionId)
    }

    private func markShown(sessionId: String) {
        var ids = UserDefaults.standard.stringArray(forKey: shownSessionIdsKey) ?? []
        guard !ids.contains(sessionId) else { return }
        ids.append(sessionId)
        UserDefaults.standard.set(ids, forKey: shownSessionIdsKey)
    }
}

/// 広告のフルスクリーン表示イベントをクロージャに橋渡しするだけの薄いdelegate
private final class InterstitialAdPresentationDelegate: NSObject, GADFullScreenContentDelegate {
    private let onWillPresent: () -> Void
    private let onDismissOrFail: () -> Void

    init(onWillPresent: @escaping () -> Void, onDismissOrFail: @escaping () -> Void) {
        self.onWillPresent = onWillPresent
        self.onDismissOrFail = onDismissOrFail
    }

    func adWillPresentFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        onWillPresent()
    }

    func adDidDismissFullScreenContent(_ ad: any GADFullScreenPresentingAd) {
        onDismissOrFail()
    }

    func ad(_ ad: any GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        onDismissOrFail()
    }
}
