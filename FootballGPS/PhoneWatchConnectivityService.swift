//
//  PhoneWatchConnectivityService.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import Foundation
import WatchConnectivity
import Combine

/// iPhone側のWatchConnectivityサービス
/// Apple Watchからセッションデータを受信する
@MainActor
class PhoneWatchConnectivityService: NSObject, ObservableObject {
    
    static let shared = PhoneWatchConnectivityService()
    
    @Published var isReachable = false
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        } else {
            print("⚠️ WatchConnectivity not supported")
        }
    }
    
    /// Watchから転送されたセッション＋GPSデータのJSONファイルを読み込み保存する。
    /// sendMessage/transferUserInfo（辞書ベース）はペイロードサイズの実務上の上限により長時間
    /// セッションで転送に失敗する事例が確認されたため、rawMotionと同じくファイル転送に統一した
    private func processReceivedSessionFile(_ url: URL) {
        defer { try? FileManager.default.removeItem(at: url) }

        guard let data = try? Data(contentsOf: url) else {
            print("❌ trainingSessionファイル読み込み失敗")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(SessionTransferPayload.self, from: data) else {
            print("❌ trainingSessionデコード失敗")
            return
        }

        let session = payload.session
        let gpsData = payload.gpsData
        print("✅ セッション受信成功: \(session.name), GPS点数=\(gpsData.points.count)")

        // データマネージャーに保存 (fieldIdは自動選択を試み、失敗した場合のみユーザーが手動選択)
        SessionDataManager.shared.saveSession(session, gpsData: gpsData)

        // フィールド自動選択: 一致すればfieldIdを永続化し、ドリル分割の再解析も連鎖して行われる
        let fieldAssigned = SessionDataManager.shared.autoAssignFieldId(for: session.id)

        // fieldIdが自動確定しなかった場合のみ、ドリル自動分割を内部判定のみで試す
        // （フィールドが特定でき、休憩が検出できた場合のみ候補として保存される。それ以外は無処理）
        if !fieldAssigned {
            SessionDataManager.shared.analyzeForDrillSplits(sessionId: session.id)
        }

        print("✅ セッションデータ受信完了: \(session.name)")
    }
}

// MARK: - WCSessionDelegate

extension PhoneWatchConnectivityService: WCSessionDelegate {
    
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        print("⚠️ セッション非アクティブ")
    }
    
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("⚠️ セッション非活性化")
        // 再アクティベート
        session.activate()
    }
    
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error = error {
                print("❌ WatchConnectivity初期化エラー: \(error.localizedDescription)")
            } else {
                print("✅ WatchConnectivity初期化完了: \(activationState.rawValue)")
                self.updateConnectionStatus()
            }
        }
    }
    
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            print("📡 接続状態変更: isReachable = \(session.isReachable)")
            self.updateConnectionStatus()
        }
    }
    
    // ファイル受信（セッション+GPS JSON / rawMotion JSON / キャリブレーションCSV）
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata
        guard let type = metadata?["type"] as? String else {
            print("⚠️ 不明なファイル受信: \(metadata ?? [:])")
            return
        }

        switch type {
        case "trainingSession":
            guard let sessionId = metadata?["sessionId"] as? String else {
                print("⚠️ trainingSession: sessionId がメタデータに含まれていません")
                return
            }
            // WCSessionFile.fileURL はこのデリゲートメソッドの実行中しか有効性が保証されないため、
            // 非同期処理に渡す前に同期的に永続領域へコピーする（このメソッドはnonisolatedなので同期I/Oのみ許容）
            let destURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("received_session_\(sessionId).json")
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: file.fileURL, to: destURL)
            } catch {
                print("❌ trainingSessionファイルのコピー失敗: \(error)")
                return
            }
            Task { @MainActor in
                print("📥 trainingSessionファイル受信: sessionId=\(sessionId)")
                PhoneWatchConnectivityService.shared.processReceivedSessionFile(destURL)
            }

        case "rawMotion":
            guard let sessionId = metadata?["sessionId"] as? String else {
                print("⚠️ rawMotion: sessionId がメタデータに含まれていません")
                return
            }
            // ファイルを一時パスからアジリティディレクトリへコピーしてから処理
            let srcURL = file.fileURL
            Task { @MainActor in
                print("📥 rawMotion ファイル受信: sessionId=\(sessionId)")
                SessionDataManager.shared.processRawMotionFile(srcURL, sessionId: sessionId)
            }

        case "calibration":
            guard let filename = metadata?["filename"] as? String else { return }
            Task { @MainActor in
                print("📥 キャリブレーションCSV受信: \(filename)")
                #if DEBUG
                SessionDataManager.shared.saveCalibrationFile(from: file.fileURL, filename: filename)
                #endif
            }

        default:
            print("⚠️ 不明なファイルタイプ: \(type)")
        }
    }
    
    private func updateConnectionStatus() {
        let session = WCSession.default
        self.isReachable = session.isReachable
        self.isPaired = session.isPaired
        self.isWatchAppInstalled = session.isWatchAppInstalled
        
        print("📊 接続状態:")
        print("  - isReachable: \(isReachable)")
        print("  - isPaired: \(isPaired)")
        print("  - isWatchAppInstalled: \(isWatchAppInstalled)")
    }
}
