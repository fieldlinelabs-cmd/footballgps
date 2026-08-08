//
//  FieldManager.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import Foundation
import Combine

/// フィールドデータを管理するクラス（iPhone側）
@MainActor
class FieldManager: ObservableObject {
    
    static let shared = FieldManager()
    
    @Published var fields: [Field] = []

    private let fieldsKey = "savedFields"

    private init() {
        loadFields()
    }
    
    // MARK: - Field Operations
    
    /// フィールドを追加
    func addField(_ field: Field) {
        fields.append(field)
        persistFields()
        print("✅ フィールド追加: \(field.name)")

        // フィールド未登録のため fieldId 未確定・ドリル分割未検出だったセッションを再解析する
        SessionDataManager.shared.autoAssignFieldIdForUnresolvedSessions()
        SessionDataManager.shared.reanalyzeSessionsForDrillSplits()
    }

    /// フィールドを更新
    func updateField(_ field: Field) {
        if let index = fields.firstIndex(where: { $0.id == field.id }) {
            fields[index] = field
            persistFields()
            print("✅ フィールド更新: \(field.name)")

            // 境界の変更で新たに一致率が上がるセッションがあるかもしれないため再解析する
            SessionDataManager.shared.autoAssignFieldIdForUnresolvedSessions()
            SessionDataManager.shared.reanalyzeSessionsForDrillSplits()
        }
    }
    
    /// フィールドを削除
    func deleteField(_ field: Field) {
        fields.removeAll { $0.id == field.id }
        persistFields()
        print("🗑️ フィールド削除: \(field.name)")
    }
    
    /// IDからフィールドを取得
    func getField(by id: String) -> Field? {
        return fields.first { $0.id == id }
    }
    
    /// GPS座標から最適なフィールドを自動判定する際の最低一致率。
    /// 休憩の多い（＝フィールド外の時間が長い）練習でも検出できるよう、低めに設定している。
    /// ドリル分割の内部判定とfieldId自動選択の両方がこの値を共有する（意図的、別基準にしない）
    static let matchRateThreshold: Double = 0.4

    /// GPS座標から最適なフィールドを自動判定
    func detectField(for gpsPoints: [GPSPoint]) -> Field? {
        guard !gpsPoints.isEmpty else { return nil }

        var bestMatch: (field: Field, rate: Double)?

        for field in fields {
            let rate = field.matchRate(for: gpsPoints)

            if rate >= FieldManager.matchRateThreshold {
                if bestMatch == nil || rate > bestMatch!.rate {
                    bestMatch = (field, rate)
                }
            }
        }
        
        if let match = bestMatch {
            print("📍 フィールド自動判定: \(match.field.name) (一致率: \(String(format: "%.1f", match.rate * 100))%)")
            return match.field
        }
        
        print("⚠️ 該当するフィールドが見つかりませんでした")
        return nil
    }
    
    // MARK: - Persistence
    
    private func persistFields() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(fields) {
            UserDefaults.standard.set(encoded, forKey: fieldsKey)
        }
    }
    
    private func loadFields() {
        guard let data = UserDefaults.standard.data(forKey: fieldsKey) else {
            print("📂 保存されたフィールドなし")
            return
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let decoded = try? decoder.decode([Field].self, from: data) {
            fields = decoded
            print("📂 \(fields.count)件のフィールドを読み込みました")
        }
    }
    
    // MARK: - Utilities
    
    /// すべてのフィールドをクリア（開発用）
    func clearAllFields() {
        fields.removeAll()
        UserDefaults.standard.removeObject(forKey: fieldsKey)
        print("🗑️ すべてのフィールドをクリアしました")
    }
}
