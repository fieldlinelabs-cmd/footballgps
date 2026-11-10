//
//  TrackingPermission.swift
//  FootballGPS
//
//  トラッキングの許可（ATT）を求めるタイミングの管理（広告仕様書 §10.4、2026-11-08決定）。
//  最初の記録を見た後（セッション詳細を開いて少し経ったとき）に1度だけ求める。
//  アプリの価値が伝わってから聞くほうが許可されやすく、一度断られるとアプリからは二度と出せないため、起動直後には出さない。
//

import AppTrackingTransparency
import UIKit

enum TrackingPermission {
    /// 詳細画面を開いてから許可の画面を出すまでの待ち時間。記録を見てもらってから聞くため
    static let delayAfterDetailAppears: Duration = .seconds(2)

    /// セッション詳細の表示中に呼ぶ。条件を満たせば許可の画面を出す。
    /// 画面を離れると呼び出し元の `.task` が取り消され、待ち時間の途中で止まる
    @MainActor
    static func requestAfterViewingRecord() async {
        guard shouldRequest else { return }
        try? await Task.sleep(for: delayAfterDetailAppears)
        guard !Task.isCancelled, shouldRequest,
              UIApplication.shared.applicationState == .active else { return }
        // 結果はAdMobが次の広告の読み込みから自動で使うため、ここでは何もしない
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    @MainActor
    private static var shouldRequest: Bool {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return false }
        // 13歳未満と分かっている利用者には出さない（子ども向けの扱い、広告仕様書 §10.3）。
        // 生年月日は任意のため、未入力の利用者には出す
        if AdConfiguration.isChildDirected(age: UserProfileManager.shared.age) { return false }
        return true
    }
}
