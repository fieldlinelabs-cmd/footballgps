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
    @Published var selectedFieldId: String?
    
    private let fieldsKey = "savedFields"
    private let selectedFieldKey = "selectedFieldId"
    
    private init() {
        loadFields()
        loadSelectedField()
    }
    
    // MARK: - Field Operations
    
    /// フィールドを追加
    func addField(_ field: Field) {
        fields.append(field)
        persistFields()
        
        // 最初のフィールドを自動的に選択
        if fields.count == 1 {
            selectedFieldId = field.id
            persistSelectedField()
        }
        
        print("✅ フィールド追加: \(field.name)")
    }
    
    /// フィールドを更新
    func updateField(_ field: Field) {
        if let index = fields.firstIndex(where: { $0.id == field.id }) {
            fields[index] = field
            persistFields()
            print("✅ フィールド更新: \(field.name)")
        }
    }
    
    /// フィールドを削除
    func deleteField(_ field: Field) {
        fields.removeAll { $0.id == field.id }
        
        // 削除したフィールドが選択されていた場合
        if selectedFieldId == field.id {
            selectedFieldId = fields.first?.id
            persistSelectedField()
        }
        
        persistFields()
        print("🗑️ フィールド削除: \(field.name)")
    }
    
    /// 選択中のフィールドを設定
    func selectField(_ fieldId: String?) {
        selectedFieldId = fieldId
        persistSelectedField()
        
        print("📍 フィールド選択: \(fieldId ?? "なし")")
    }
    
    /// 選択中のフィールドを取得
    func getSelectedField() -> Field? {
        guard let selectedId = selectedFieldId else { return nil }
        return fields.first { $0.id == selectedId }
    }
    
    /// IDからフィールドを取得
    func getField(by id: String) -> Field? {
        return fields.first { $0.id == id }
    }
    
    /// GPS座標から最適なフィールドを自動判定
    func detectField(for gpsPoints: [GPSPoint]) -> Field? {
        guard !gpsPoints.isEmpty else { return nil }
        
        var bestMatch: (field: Field, rate: Double)?
        
        for field in fields {
            let rate = field.matchRate(for: gpsPoints)
            
            // 80%以上のポイントが範囲内にあれば該当フィールド
            if rate >= 0.8 {
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
    
    private func persistSelectedField() {
        if let selectedId = selectedFieldId {
            UserDefaults.standard.set(selectedId, forKey: selectedFieldKey)
        } else {
            UserDefaults.standard.removeObject(forKey: selectedFieldKey)
        }
    }
    
    private func loadSelectedField() {
        selectedFieldId = UserDefaults.standard.string(forKey: selectedFieldKey)
    }
    
    // MARK: - Utilities
    
    /// すべてのフィールドをクリア（開発用）
    func clearAllFields() {
        fields.removeAll()
        selectedFieldId = nil
        
        UserDefaults.standard.removeObject(forKey: fieldsKey)
        UserDefaults.standard.removeObject(forKey: selectedFieldKey)
        
        print("🗑️ すべてのフィールドをクリアしました")
    }
}
