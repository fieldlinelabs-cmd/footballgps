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
    private var gpsDataCache: [String: GPSData] = [:]  // sessionId -> GPSData（LRU、最大3件）
    @Published var isMigrating: Bool = false

    private let sessionsKey = "savedSessions"
    private let gpsDataPrefix = "gpsData_"                  // 旧 UserDefaults キー（移行時のみ使用）
    private let migrationKey = "gpsDataMigrationCompleted"
    private let iCloudBackupEnabledKey = "gpsDataiCloudBackupEnabled"

    // LRU キャッシュ管理（最大3件）
    private var lruOrder: [String] = []
    private let maxCacheSize = 3

    private init() {
        loadSessions()
        print("📱 SessionDataManager初期化完了: \(sessions.count)件のセッション")

        // GPS ディレクトリを確保してマイグレーション実行
        ensureGPSDirectoryExists()
        migrateGPSDataIfNeeded()

        // シミュレーター用: Watch側から保存されたデータを読み込む
        #if targetEnvironment(simulator)
        loadPendingSessionsFromWatch()
        #endif
    }

    // MARK: - Save/Load Sessions

    /// セッションを保存（sprintCount は GPS データから再計算して上書きする）
    func saveSession(_ session: TrainingSession, gpsData: GPSData) {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
        sessions.sort { $0.date > $1.date }

        cacheGPSData(gpsData, for: session.id)
        persistGPSData(gpsData)

        // GPS データからスプリント回数を計算して上書き
        let count = SessionDataManager.calculateSprintCount(from: gpsData)
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index].sprintCount = count
        }
        persistSessions()

        print("✅ セッション保存完了: \(session.name), スプリント: \(count)回")
        print("📊 総セッション数: \(sessions.count)")
    }

    /// GPS データからスプリント回数を計算する
    static func calculateSprintCount(from gpsData: GPSData) -> Int {
        let sprintThreshold: Double = 5.5
        let sprintEndThreshold: Double = 4.5
        let minSprintDuration: TimeInterval = 2.0
        let minSprintInterval: TimeInterval = 5.0

        var count = 0
        var isInSprint = false
        var isInSprintCandidate = false
        var candidateStartTime: Date? = nil
        var lastSprintEndTime: Date? = nil

        for point in gpsData.points {
            let speed = point.speed
            let timestamp = point.timestamp

            if isInSprint {
                if speed < sprintEndThreshold {
                    isInSprint = false
                    lastSprintEndTime = timestamp
                }
            } else if isInSprintCandidate {
                if speed < sprintEndThreshold {
                    isInSprintCandidate = false
                    candidateStartTime = nil
                } else if let start = candidateStartTime,
                          timestamp.timeIntervalSince(start) >= minSprintDuration {
                    isInSprint = true
                    isInSprintCandidate = false
                    count += 1
                }
            } else {
                if speed >= sprintThreshold {
                    let canStart = lastSprintEndTime == nil ||
                        timestamp.timeIntervalSince(lastSprintEndTime!) >= minSprintInterval
                    if canStart {
                        isInSprintCandidate = true
                        candidateStartTime = timestamp
                    }
                }
            }
        }

        return count
    }

    /// GPSデータを取得
    func getGPSData(for sessionId: String) -> GPSData? {
        if let cached = gpsDataCache[sessionId] {
            // キャッシュヒット: LRU 順を更新
            lruOrder.removeAll { $0 == sessionId }
            lruOrder.append(sessionId)
            return cached
        }

        // キャッシュミス: ファイルから読み込んでキャッシュに追加
        if let loaded = loadGPSData(sessionId: sessionId) {
            cacheGPSData(loaded, for: sessionId)
            return loaded
        }

        return nil
    }

    /// セッションを削除
    func deleteSession(_ session: TrainingSession) {
        sessions.removeAll { $0.id == session.id }
        gpsDataCache.removeValue(forKey: session.id)
        lruOrder.removeAll { $0 == session.id }

        persistSessions()
        deleteGPSData(sessionId: session.id)

        print("🗑️ セッション削除: \(session.name)")
    }

    // MARK: - iCloud Backup Setting

    /// iCloudバックアップの有効/無効を取得
    var isICloudBackupEnabled: Bool {
        UserDefaults.standard.bool(forKey: iCloudBackupEnabledKey)
    }

    /// iCloudバックアップの有効/無効を変更し、ディレクトリの設定を即時反映
    func setICloudBackupEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: iCloudBackupEnabledKey)
        updateBackupExclusion(excluded: !enabled)
    }

    // MARK: - Persistence (Sessions)

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

    // MARK: - Persistence (GPS Data — File System)

    private func persistGPSData(_ gpsData: GPSData) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(gpsData) else { return }
        let url = gpsFileURL(for: gpsData.sessionId)
        try? data.write(to: url, options: .atomic)
    }

    private func loadGPSData(sessionId: String) -> GPSData? {
        let url = gpsFileURL(for: sessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GPSData.self, from: data)
    }

    private func deleteGPSData(sessionId: String) {
        // ファイルが存在しない場合は無視（エラーとして扱わない）
        try? FileManager.default.removeItem(at: gpsFileURL(for: sessionId))
    }

    // MARK: - GPS Directory

    private var gpsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FootballGPS/gps", isDirectory: true)
    }

    private func gpsFileURL(for sessionId: String) -> URL {
        gpsDirectory.appendingPathComponent("gpsdata_\(sessionId).json")
    }

    /// GPS ディレクトリを作成し、バックアップ除外設定を適用
    private func ensureGPSDirectoryExists() {
        let dir = gpsDirectory
        guard !FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        updateBackupExclusion(excluded: !isICloudBackupEnabled)
    }

    /// iCloud バックアップ除外フラグを GPS ディレクトリに設定
    private func updateBackupExclusion(excluded: Bool) {
        var url = gpsDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        try? url.setResourceValues(values)
    }

    // MARK: - LRU Cache

    /// LRU キャッシュに GPS データを追加（最大3件を超えたら最古エントリを除去）
    private func cacheGPSData(_ gpsData: GPSData, for sessionId: String) {
        gpsDataCache[sessionId] = gpsData
        lruOrder.removeAll { $0 == sessionId }
        lruOrder.append(sessionId)

        while lruOrder.count > maxCacheSize {
            let evicted = lruOrder.removeFirst()
            gpsDataCache.removeValue(forKey: evicted)
        }
    }

    // MARK: - Migration (UserDefaults → File System)

    /// 旧 UserDefaults 形式の GPS データをファイルシステムへ移行
    private func migrateGPSDataIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        let sessionIds = sessions.map { $0.id }

        // 移行すべき UserDefaults エントリが存在するか事前確認
        let idsToMigrate = sessionIds.filter {
            UserDefaults.standard.data(forKey: "gpsData_\($0)") != nil
        }

        guard !idsToMigrate.isEmpty else {
            // 移行対象なし（初回インストール等）: フラグだけ立てて完了
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        isMigrating = true
        let gpsDir = gpsDirectory

        Task.detached(priority: .utility) { [idsToMigrate, gpsDir] in
            for sessionId in idsToMigrate {
                let udKey = "gpsData_\(sessionId)"
                // UserDefaults に保存された生 JSON データをそのままファイルへコピー
                guard let data = UserDefaults.standard.data(forKey: udKey) else { continue }

                let fileURL = gpsDir.appendingPathComponent("gpsdata_\(sessionId).json")
                guard (try? data.write(to: fileURL, options: .atomic)) != nil,
                      FileManager.default.fileExists(atPath: fileURL.path) else { continue }

                // 書き出し成功を確認してから UserDefaults を削除
                UserDefaults.standard.removeObject(forKey: udKey)
            }

            UserDefaults.standard.set(true, forKey: "gpsDataMigrationCompleted")

            await MainActor.run {
                SessionDataManager.shared.isMigrating = false
                print("✅ GPSデータのファイルシステム移行完了")
            }
        }
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
        for session in sessions {
            deleteGPSData(sessionId: session.id)
        }
        sessions.removeAll()
        gpsDataCache.removeAll()
        lruOrder.removeAll()
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        print("🗑️ すべてのデータをクリアしました")
    }

    // MARK: - Simulator Support

    #if targetEnvironment(simulator)
    /// シミュレーター用: Watch側から保存されたデータを読み込む
    private func loadPendingSessionsFromWatch() {
        guard let pendingIds = UserDefaults.standard.stringArray(forKey: "pendingSessionIds"),
              !pendingIds.isEmpty else { return }

        print("🔄 Watch側から保留中のセッションを読み込み中... (\(pendingIds.count)件)")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var loadedCount = 0

        for sessionId in pendingIds {
            guard let sessionData = UserDefaults.standard.data(forKey: "pendingSession_\(sessionId)"),
                  let session = try? decoder.decode(TrainingSession.self, from: sessionData) else {
                print("⚠️ セッション読み込み失敗: \(sessionId)")
                continue
            }
            guard let gpsDataEncoded = UserDefaults.standard.data(forKey: "pendingGPS_\(sessionId)"),
                  let gpsData = try? decoder.decode(GPSData.self, from: gpsDataEncoded) else {
                print("⚠️ GPSデータ読み込み失敗: \(sessionId)")
                continue
            }

            saveSession(session, gpsData: gpsData)
            loadedCount += 1

            UserDefaults.standard.removeObject(forKey: "pendingSession_\(sessionId)")
            UserDefaults.standard.removeObject(forKey: "pendingGPS_\(sessionId)")
        }

        UserDefaults.standard.removeObject(forKey: "pendingSessionIds")
        UserDefaults.standard.synchronize()

        if loadedCount > 0 {
            print("✅ Watch側から\(loadedCount)件のセッションを読み込みました")
        }
    }
    #endif
}
