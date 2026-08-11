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
    
    /// セッションデータをiPhoneに送信（ファイル転送）。
    /// sendMessage/transferUserInfoはペイロードサイズに実務上の上限があり、長時間セッション
    /// （GPS点数が多い）で転送に失敗する事例が確認されたため、rawMotionと同じくJSONファイルに
    /// 書き出してtransferFileで送る方式に統一した（reachability に関わらずバックグラウンドで届く）
    func sendSession(_ session: TrainingSession, gpsData: GPSData) {
        guard WCSession.default.activationState == .activated else {
            print("❌ WatchConnectivity未初期化")
            return
        }

        let payload = SessionTransferPayload(session: session, gpsData: gpsData)
        let url = Self.sessionTransferTempURL(sessionId: session.id)

        Task.detached {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(payload)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                print("💾 セッションファイル書き込み完了: \(url.lastPathComponent) (\(data.count) bytes, \(gpsData.points.count)点)")
                await MainActor.run {
                    let metadata: [String: Any] = ["type": "trainingSession", "sessionId": session.id]
                    WCSession.default.transferFile(url, metadata: metadata)
                    print("📤 セッションファイル転送キュー追加: \(url.lastPathComponent)")
                }
            } catch {
                print("❌ セッションファイル書き込みエラー: \(error)")
            }
        }
    }

    private static func sessionTransferTempURL(sessionId: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("FootballGPS/sessionTransfer", isDirectory: true)
            .appendingPathComponent("session_\(sessionId).json")
    }

    /// 未送信データの数を取得（rawMotion・セッションデータ、いずれもファイル転送に統一済み）
    var pendingTransferCount: Int {
        WCSession.default.outstandingFileTransfers.count
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

    /// 転送が既に完了・失敗して放置された孤立ファイルを掃除する。
    /// `outstandingFileTransfers`に含まれていない（＝システム側がもう扱っていない）のに
    /// ローカルに残っているファイルは、二度と使われることのないゴミなので削除する。
    /// アプリ起動（WCSessionアクティベート）のたびに呼ばれる
    static func cleanUpOrphanedTransferFiles(session: WCSession) {
        let activeURLs = Set(session.outstandingFileTransfers.map { $0.file.fileURL.path })

        let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let sessionTransferDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FootballGPS/sessionTransfer", isDirectory: true)

        var removedCount = 0
        for dir in [appSupportDir, sessionTransferDir].compactMap({ $0 }) {
            guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let name = file.lastPathComponent
                guard name.hasPrefix("rawmotion_") || name.hasPrefix("session_") else { continue }
                guard !activeURLs.contains(file.path) else { continue }
                if (try? FileManager.default.removeItem(at: file)) != nil {
                    removedCount += 1
                }
            }
        }
        if removedCount > 0 {
            print("🧹 孤立した転送用一時ファイルを削除: \(removedCount)件")
        }
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

        // 旧バージョン（sendMessage/transferUserInfo方式）でキューイングされたまま残っている可能性のある
        // 未送信データを破棄する。iPhone側は受信処理(didReceiveUserInfo)を廃止済みのため、放置すると
        // 二度と届かないままシステムのキューに残り続けてしまう
        let staleTransfers = session.outstandingUserInfoTransfers
        if !staleTransfers.isEmpty {
            print("🧹 旧方式(transferUserInfo)の未送信キューを破棄: \(staleTransfers.count)件")
            staleTransfers.forEach { $0.cancel() }
        }

        // 転送が既に完了・失敗して放置された孤立ファイル（didFinishでの削除処理が入る前の
        // 旧バージョン時代に失敗したものを含む）を掃除する
        Self.cleanUpOrphanedTransferFiles(session: session)

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
        didFinish fileTransfer: WCSessionFileTransfer,
        error: Error?
    ) {
        let name = fileTransfer.file.fileURL.lastPathComponent
        let type = fileTransfer.file.metadata?["type"] as? String ?? "unknown"
        if let error {
            print("❌ ファイル転送失敗 (\(type)): \(name) - \(error.localizedDescription)")
        } else {
            print("✅ ファイル転送完了 (\(type)): \(name)")
        }
        // 成功・失敗いずれの場合も、didFinishが呼ばれた時点でシステム側はこの転送試行を終えている
        // （＝これ以上リトライされない）ため、Watch側の一時ファイルはここで削除してストレージに残さない
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
    }
}
