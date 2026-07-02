//
//  WatchConnectivityService.swift
//  FootballGPS Watch App
//
//  Created on 2025/01/08.
//

import Foundation
import WatchConnectivity
import Combine

/// Watch側のWatchConnectivityサービス
/// iPhoneへセッションデータを送信する
class WatchConnectivityService: NSObject, ObservableObject {
    
    static let shared = WatchConnectivityService()
    
    @Published var isReachable = false
    @Published var activationState: WCSessionActivationState = .notActivated
    // Watch側では isPaired と isWatchAppInstalled は使用不可
    
    private override init() {
        super.init()
        
        print("🔄 WatchConnectivityService初期化開始")
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
            print("📡 WCSession.activate()呼び出し完了")
        } else {
            print("⚠️ WatchConnectivity not supported")
        }
    }
    
    /// セッションデータをiPhoneに送信
    func sendSession(_ session: TrainingSession, gpsData: GPSData) {
        guard WCSession.default.activationState == .activated else {
            print("❌ WatchConnectivity未初期化")
            return
        }
        
        // データを辞書形式に変換
        let data: [String: Any] = [
            "type": "trainingSession",
            "session": session.dictionary,
            "gpsData": [
                "sessionId": gpsData.sessionId,
                "points": gpsData.points.map { point -> [String: Any] in
                    var dict: [String: Any] = [
                        "timestamp": point.timestamp.timeIntervalSince1970,
                        "latitude": point.latitude,
                        "longitude": point.longitude,
                        "speed": point.speed,
                        "altitude": point.altitude,
                        "horizontalAccuracy": point.horizontalAccuracy
                    ]
                    if let hr = point.heartRate, hr > 0 { dict["heartRate"] = hr }
                    return dict
                }
            ]
        ]
        
        // 1️⃣ まずリアルタイム送信を試みる（iPhoneが近くにあれば即座に送信）
        if WCSession.default.isReachable {
            print("📡 iPhone到達可能 - リアルタイム送信を試みます")
            WCSession.default.sendMessage(data, replyHandler: { reply in
                Task { @MainActor in
                    print("✅ リアルタイム送信成功")
                    if let status = reply["status"] as? String {
                        print("📱 iPhoneからの応答: \(status)")
                    }
                }
            }, errorHandler: { error in
                Task { @MainActor in
                    print("⚠️ リアルタイム送信失敗: \(error.localizedDescription)")
                    print("📦 キューイング送信にフォールバック")
                    self.queueTransfer(data)
                }
            })
        } else {
            // 2️⃣ 圏外ならキューイング送信（後で自動送信）
            print("📦 iPhone圏外 - キューイング送信")
            queueTransfer(data)
        }
    }
    
    /// キューイング送信（後で自動送信）
    private func queueTransfer(_ data: [String: Any]) {
        let transfer = WCSession.default.transferUserInfo(data)
        print("📥 キューに追加")
        print("🔄 未送信データ数: \(WCSession.default.outstandingUserInfoTransfers.count)")
        
        // transferはバックグラウンドで自動的に送信される
        // 送信完了はdidFinish transferUserInfoで通知される
    }
    
    /// 未送信データの数を取得
    var pendingTransferCount: Int {
        WCSession.default.outstandingUserInfoTransfers.count
    }

    /// rawMotion ファイルを iPhone へ転送
    func transferRawMotionFile(sessionId: String, url: URL) {
        guard WCSession.default.activationState == .activated else {
            print("❌ WatchConnectivity未初期化 - rawMotion転送スキップ")
            return
        }
        let metadata: [String: Any] = ["type": "rawMotion", "sessionId": sessionId]
        WCSession.default.transferFile(url, metadata: metadata)
        print("📤 rawMotion ファイル転送キュー追加: \(url.lastPathComponent)")
    }

}

// MARK: - WCSessionDelegate

extension WatchConnectivityService: WCSessionDelegate {
    
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error = error {
            print("❌ WatchConnectivity初期化エラー: \(error.localizedDescription)")
        } else {
            print("✅ WatchConnectivity初期化完了: \(activationState.rawValue)")
        }
        
        // 接続状態を更新
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            self?.activationState = session.activationState
            
            print("📊 接続状態:")
            print("  - activationState: \(session.activationState.rawValue)")
            print("  - isReachable: \(session.isReachable)")
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("📡 接続状態変更: isReachable = \(session.isReachable)")
        
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            
            print("📊 接続状態:")
            print("  - activationState: \(session.activationState.rawValue)")
            print("  - isReachable: \(session.isReachable)")
        }
    }
    
    nonisolated func session(
        _ session: WCSession,
        didFinish userInfoTransfer: WCSessionUserInfoTransfer,
        error: Error?
    ) {
        if let error = error {
            print("❌ キューイング送信失敗: \(error.localizedDescription)")
        } else {
            print("✅ キューイング送信完了")
            print("🔄 残り未送信データ数: \(session.outstandingUserInfoTransfers.count)")
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        if let error {
            print("❌ rawMotion ファイル転送失敗: \(name) - \(error.localizedDescription)")
        } else {
            print("✅ rawMotion ファイル転送完了: \(name)")
            // Watch 側の一時ファイルを削除
            try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        }
    }
}
