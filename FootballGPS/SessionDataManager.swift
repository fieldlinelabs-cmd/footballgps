//
//  SessionDataManager.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import Foundation
import Combine

/// セッションデータを管理するクラス（iPhone側）
@MainActor
class SessionDataManager: ObservableObject {
    
    static let shared = SessionDataManager()
    
    @Published var sessions: [TrainingSession] = []
    @Published var gpsDataCache: [String: GPSData] = [:] // sessionId -> GPSData
    
    private let sessionsKey = "savedSessions"
    private let gpsDataPrefix = "gpsData_"
    
    private init() {
        loadSessions()
        print("📱 SessionDataManager初期化完了: \(sessions.count)件のセッション")
        
        // シミュレーター用: Watch側から保存されたデータを読み込む
        #if targetEnvironment(simulator)
        loadPendingSessionsFromWatch()
        #endif
    }
    
    // MARK: - Save/Load Sessions
    
    /// セッションを保存
    func saveSession(_ session: TrainingSession, gpsData: GPSData) {
        // 1. セッションを追加
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            // 既存のセッションを更新
            sessions[index] = session
        } else {
            // 新規セッションを追加
            sessions.append(session)
        }
        
        // 日付順にソート（新しい順）
        sessions.sort { $0.date > $1.date }
        
        // 2. GPSデータをキャッシュ
        gpsDataCache[session.id] = gpsData
        
        // 3. UserDefaultsに保存
        persistSessions()
        persistGPSData(gpsData)
        
        print("✅ セッション保存完了: \(session.name)")
        print("📊 総セッション数: \(sessions.count)")
    }
    
    /// GPSデータを取得
    func getGPSData(for sessionId: String) -> GPSData? {
        // キャッシュから取得
        if let cached = gpsDataCache[sessionId] {
            return cached
        }
        
        // UserDefaultsから読み込み
        if let loaded = loadGPSData(sessionId: sessionId) {
            gpsDataCache[sessionId] = loaded
            return loaded
        }
        
        return nil
    }
    
    /// セッションを削除
    func deleteSession(_ session: TrainingSession) {
        sessions.removeAll { $0.id == session.id }
        gpsDataCache.removeValue(forKey: session.id)
        
        persistSessions()
        deleteGPSData(sessionId: session.id)
        
        print("🗑️ セッション削除: \(session.name)")
    }
    
    // MARK: - Persistence
    
    private func persistSessions() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(sessions) {
            UserDefaults.standard.set(encoded, forKey: sessionsKey)
        }
    }
    
    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey) else {
            print("📂 保存されたセッションなし")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let decoded = try? decoder.decode([TrainingSession].self, from: data) {
            sessions = decoded
            print("📂 \(sessions.count)件のセッションを読み込みました")
        }
    }
    
    private func persistGPSData(_ gpsData: GPSData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(gpsData) {
            let key = gpsDataPrefix + gpsData.sessionId
            UserDefaults.standard.set(encoded, forKey: key)
        }
    }
    
    private func loadGPSData(sessionId: String) -> GPSData? {
        let key = gpsDataPrefix + sessionId
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return nil
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return try? decoder.decode(GPSData.self, from: data)
    }
    
    private func deleteGPSData(sessionId: String) {
        let key = gpsDataPrefix + sessionId
        UserDefaults.standard.removeObject(forKey: key)
    }
    
    // MARK: - Utilities
    
    /// UserDefaultsから最新データを再読み込み（Pull-to-Refresh用）
    func reloadSessions() {
        loadSessions()
        print("🔄 セッション再読み込み完了: \(sessions.count)件")
    }
    
    /// セッションのフィールドIDを更新（ユーザーが手動選択したとき）
    func updateFieldId(for sessionId: String, fieldId: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].fieldId = fieldId
        persistSessions()
        print("✅ フィールド紐付け更新: sessionId=\(sessionId) -> fieldId=\(fieldId)")
    }
    
    /// セッションのコート入れ替えフラグを更新
    func updateIsFlipped(for sessionId: String, isFlipped: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionId }) else { return }
        sessions[index].isFlipped = isFlipped
        persistSessions()
    }
    
    /// すべてのデータをクリア（開発用）
    func clearAllData() {
        // GPSデータを先に削除してからsessionsをクリア
        for session in sessions {
            deleteGPSData(sessionId: session.id)
        }
        
        sessions.removeAll()
        gpsDataCache.removeAll()
        
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        
        print("🗑️ すべてのデータをクリアしました")
    }
    
    // MARK: - Simulator Support
    
    #if targetEnvironment(simulator)
    /// シミュレーター用: Watch側から保存されたデータを読み込む
    private func loadPendingSessionsFromWatch() {
        guard let pendingIds = UserDefaults.standard.stringArray(forKey: "pendingSessionIds"), !pendingIds.isEmpty else {
            return
        }
        
        print("🔄 Watch側から保留中のセッションを読み込み中... (\(pendingIds.count)件)")
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        var loadedCount = 0
        
        for sessionId in pendingIds {
            // セッションデータを読み込み
            guard let sessionData = UserDefaults.standard.data(forKey: "pendingSession_\(sessionId)"),
                  let session = try? decoder.decode(TrainingSession.self, from: sessionData) else {
                print("⚠️ セッション読み込み失敗: \(sessionId)")
                continue
            }
            
            // GPSデータを読み込み
            guard let gpsDataEncoded = UserDefaults.standard.data(forKey: "pendingGPS_\(sessionId)"),
                  let gpsData = try? decoder.decode(GPSData.self, from: gpsDataEncoded) else {
                print("⚠️ GPSデータ読み込み失敗: \(sessionId)")
                continue
            }
            
            // セッションを保存
            saveSession(session, gpsData: gpsData)
            loadedCount += 1
            
            // UserDefaultsから削除
            UserDefaults.standard.removeObject(forKey: "pendingSession_\(sessionId)")
            UserDefaults.standard.removeObject(forKey: "pendingGPS_\(sessionId)")
        }
        
        // 保留中IDリストをクリア
        UserDefaults.standard.removeObject(forKey: "pendingSessionIds")
        UserDefaults.standard.synchronize()
        
        if loadedCount > 0 {
            print("✅ Watch側から\(loadedCount)件のセッションを読み込みました")
        }
    }
    #endif
}
