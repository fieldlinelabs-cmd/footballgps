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
    
    /// セッションデータを受信して保存
    private func handleReceivedData(_ data: [String: Any]) {
        print("📥 データ受信開始...")
        print("📦 受信データ内容: \(data.keys)")
        
        guard let type = data["type"] as? String,
              type == "trainingSession" else {
            print("⚠️ 不明なデータタイプ: \(data["type"] ?? "nil")")
            return
        }
        
        print("✅ データタイプ確認: trainingSession")
        
        // セッションデータを解析
        guard let sessionDict = data["session"] as? [String: Any],
              let gpsDataDict = data["gpsData"] as? [String: Any] else {
            print("❌ データ解析失敗")
            print("   - session: \(data["session"] != nil ? "あり" : "なし")")
            print("   - gpsData: \(data["gpsData"] != nil ? "あり" : "なし")")
            return
        }
        
        print("✅ セッション辞書取得成功")
        
        // TrainingSessionを復元
        guard var session = parseTrainingSession(from: sessionDict) else {
            print("❌ TrainingSession復元失敗")
            return
        }
        
        print("✅ TrainingSession復元成功: \(session.name)")
        
        // GPSDataを復元
        guard let gpsData = parseGPSData(from: gpsDataDict) else {
            print("❌ GPSData復元失敗")
            return
        }
        
        print("✅ GPSData復元成功: \(gpsData.points.count)ポイント")
        
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
    
    // MARK: - Parsing
    
    private func parseTrainingSession(from dict: [String: Any]) -> TrainingSession? {
        guard let id = dict["id"] as? String,
              let userId = dict["userId"] as? String,
              let name = dict["name"] as? String,
              let dateTimestamp = dict["date"] as? TimeInterval,
              let duration = dict["duration"] as? TimeInterval,
              let totalDistance = dict["totalDistance"] as? Double,
              let maxSpeed = dict["maxSpeed"] as? Double,
              let avgSpeed = dict["avgSpeed"] as? Double else {
            return nil
        }
        
        let date = Date(timeIntervalSince1970: dateTimestamp)
        let teamId = dict["teamId"] as? String
        let fieldId = dict["fieldId"] as? String
        let visibilityStr = dict["visibility"] as? String ?? "private"
        let visibility = TrainingSession.SessionVisibility(rawValue: visibilityStr) ?? .private
        let sprintCount = dict["sprintCount"] as? Int
        let gpsDataPath = dict["gpsDataPath"] as? String
        let heartRate = dict["heartRate"] as? Double
        let activeCalories = dict["activeCalories"] as? Double

        return TrainingSession(
            id: id,
            userId: userId,
            teamId: teamId,
            fieldId: fieldId,
            name: name,
            date: date,
            duration: duration,
            visibility: visibility,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed,
            sprintCount: sprintCount,
            gpsDataPath: gpsDataPath,
            heartRate: heartRate,
            activeCalories: activeCalories
        )
    }
    
    private func parseGPSData(from dict: [String: Any]) -> GPSData? {
        guard let sessionId = dict["sessionId"] as? String,
              let pointsArray = dict["points"] as? [[String: Any]] else {
            return nil
        }
        
        let points = pointsArray.compactMap { pointDict -> GPSPoint? in
            guard let timestamp = pointDict["timestamp"] as? TimeInterval,
                  let latitude = pointDict["latitude"] as? Double,
                  let longitude = pointDict["longitude"] as? Double,
                  let speed = pointDict["speed"] as? Double,
                  let altitude = pointDict["altitude"] as? Double,
                  let horizontalAccuracy = pointDict["horizontalAccuracy"] as? Double else {
                return nil
            }
            
            let heartRate = pointDict["heartRate"] as? Double
            return GPSPoint(
                timestamp: Date(timeIntervalSince1970: timestamp),
                latitude: latitude,
                longitude: longitude,
                speed: speed,
                altitude: altitude,
                horizontalAccuracy: horizontalAccuracy,
                heartRate: heartRate
            )
        }
        
        return GPSData(sessionId: sessionId, points: points)
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
    
    // リアルタイムメッセージ受信
    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        Task { @MainActor in
            print("📥 リアルタイムメッセージ受信")
            self.handleReceivedData(message)
            
            // 応答を返す
            replyHandler(["status": "received"])
        }
    }
    
    // キューイングデータ受信
    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        Task { @MainActor in
            print("📥 キューイングデータ受信")
            self.handleReceivedData(userInfo)
        }
    }

    // ファイル受信（rawMotion JSON / キャリブレーションCSV）
    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata
        guard let type = metadata?["type"] as? String else {
            print("⚠️ 不明なファイル受信: \(metadata ?? [:])")
            return
        }

        switch type {
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
