//
//  NativeAdManager.swift
//  FootballGPS
//
//  Sessions一覧に挟むネイティブ広告（docs/広告仕様書.md §4.1①）の読み込み管理。
//  広告を挟む位置の数だけ（最大5件）まとめて読み込み、読み込めた分だけ一覧に表示する。
//  読み込めなかった位置には何も出さない（一覧はそのまま表示する）。
//

import Combine
import GoogleMobileAds
import UIKit

@MainActor
final class NativeAdManager: NSObject, ObservableObject {
    static let shared = NativeAdManager()

    // Debugビルドは実機で動作確認できるようGoogle公式のテスト用ID。
    // 本番IDはAdMobでネイティブ広告の広告ユニットを作成後にここへ設定する（未設定の間は何もしない）。
    #if DEBUG
    private let adUnitID: String? = "ca-app-pub-3940256099942544/3986624511"
    #else
    private let adUnitID: String? = nil
    #endif

    // 1回のリクエストで受け取れる広告数の上限（GADMultipleAdsAdLoaderOptions）
    private let maxAds = 5
    // 読み込んだネイティブ広告は1時間で期限切れになるため、それより古ければ読み直す
    private let adLifetime: TimeInterval = 60 * 60

    /// 一覧に表示できる広告（挟む位置の順に使う）
    @Published private(set) var ads: [GADNativeAd] = []

    private var adLoader: GADAdLoader?
    private var loaderDelegate: NativeAdLoaderDelegate?
    private var receivedAds: [GADNativeAd] = []
    private var loadedAt: Date?

    /// 一覧の表示時に呼ぶ。広告を挟む位置の数（`slotCount`）に足りないか、期限切れなら読み込む
    func loadIfNeeded(slotCount: Int) {
        guard let adUnitID, slotCount > 0, adLoader == nil else { return }
        let wanted = min(slotCount, maxAds)
        let isFresh = loadedAt.map { Date().timeIntervalSince($0) < adLifetime } ?? false
        if isFresh && ads.count >= wanted { return }

        let options = GADMultipleAdsAdLoaderOptions()
        options.numberOfAds = wanted
        let loader = GADAdLoader(
            adUnitID: adUnitID,
            rootViewController: UIViewController.currentForPresentation,
            adTypes: [.native],
            options: [options]
        )
        let delegate = NativeAdLoaderDelegate(
            onReceive: { [weak self] nativeAd in
                self?.receivedAds.append(nativeAd)
            },
            onFail: { error in
                let nsError = error as NSError
                print("🎬 ネイティブ広告 読み込み失敗: domain=\(nsError.domain) code=\(nsError.code) \(nsError.localizedDescription)")
            },
            onFinish: { [weak self] in
                guard let self else { return }
                if !self.receivedAds.isEmpty {
                    self.ads = self.receivedAds
                    self.loadedAt = Date()
                    print("🎬 ネイティブ広告 読み込み成功: \(self.receivedAds.count)件")
                }
                self.receivedAds = []
                self.adLoader = nil
                self.loaderDelegate = nil
            }
        )
        loader.delegate = delegate
        loaderDelegate = delegate
        adLoader = loader
        receivedAds = []
        loader.load(GADRequest())
    }
}

/// 広告読み込みのイベントをクロージャに橋渡しするだけの薄いdelegate
private final class NativeAdLoaderDelegate: NSObject, GADNativeAdLoaderDelegate {
    private let onReceive: (GADNativeAd) -> Void
    private let onFail: (Error) -> Void
    private let onFinish: () -> Void

    init(
        onReceive: @escaping (GADNativeAd) -> Void,
        onFail: @escaping (Error) -> Void,
        onFinish: @escaping () -> Void
    ) {
        self.onReceive = onReceive
        self.onFail = onFail
        self.onFinish = onFinish
    }

    func adLoader(_ adLoader: GADAdLoader, didReceive nativeAd: GADNativeAd) {
        onReceive(nativeAd)
    }

    func adLoader(_ adLoader: GADAdLoader, didFailToReceiveAdWithError error: Error) {
        onFail(error)
    }

    func adLoaderDidFinishLoading(_ adLoader: GADAdLoader) {
        onFinish()
    }
}
