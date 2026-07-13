//
//  Team.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation

/// チームのモデル
struct Team: Identifiable, Codable {
    let id: String
    var name: String
    let inviteCode: String
    let createdBy: String
    let createdAt: Date
    
    // 権限管理
    var adminUserIds: [String]
    var memberUserIds: [String]
    
    init(
        id: String = UUID().uuidString,
        name: String,
        inviteCode: String = Team.generateInviteCode(),
        createdBy: String,
        createdAt: Date = Date(),
        adminUserIds: [String] = [],
        memberUserIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.inviteCode = inviteCode
        self.createdBy = createdBy
        self.createdAt = createdAt
        
        // 作成者は自動的にアドミニストレーター
        var admins = adminUserIds
        if !admins.contains(createdBy) {
            admins.append(createdBy)
        }
        self.adminUserIds = admins
        self.memberUserIds = memberUserIds
    }
    
    /// 全メンバー（アドミン + 一般メンバー）
    var allMemberIds: [String] {
        adminUserIds + memberUserIds
    }
    
    /// ユーザーがアドミンかどうか
    func isAdmin(_ userId: String) -> Bool {
        adminUserIds.contains(userId)
    }
    
    /// ユーザーがメンバーかどうか
    func isMember(_ userId: String) -> Bool {
        allMemberIds.contains(userId)
    }
    
    /// 6桁の招待コードを生成
    static func generateInviteCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // 紛らわしい文字を除外
        return String((0..<6).map { _ in characters.randomElement()! })
    }
    
    /// Firestoreとの変換用
    var dictionary: [String: Any] {
        [
            "id": id,
            "name": name,
            "inviteCode": inviteCode,
            "createdBy": createdBy,
            "createdAt": createdAt.timeIntervalSince1970, // TimeIntervalに変換
            "adminUserIds": adminUserIds,
            "memberUserIds": memberUserIds
        ]
    }
}

/// 性別
enum Gender: String, Codable, CaseIterable {
    case male = "male"
    case female = "female"
    case other = "other"

    var displayName: String {
        switch self {
        case .male:   return "男性"
        case .female: return "女性"
        case .other:  return "その他"
        }
    }
}

/// ユーザープロフィール
struct UserProfile: Identifiable, Codable {
    let id: String // Firebase Auth UID
    var displayName: String
    var email: String?
    var teamIds: [String]
    let createdAt: Date
    var birthDate: Date?
    var gender: Gender?
    /// プロフィール顔写真（圧縮済みJPEG）。UserDefaultsに保存されるため通常のバックアップ対象
    var avatarImageData: Data?

    init(
        id: String,
        displayName: String,
        email: String? = nil,
        teamIds: [String] = [],
        createdAt: Date = Date(),
        birthDate: Date? = nil,
        gender: Gender? = nil,
        avatarImageData: Data? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.teamIds = teamIds
        self.createdAt = createdAt
        self.birthDate = birthDate
        self.gender = gender
        self.avatarImageData = avatarImageData
    }
    
    /// Firestoreとの変換用
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "displayName": displayName,
            "teamIds": teamIds,
            "createdAt": createdAt.timeIntervalSince1970 // TimeIntervalに変換
        ]
        
        if let email = email {
            dict["email"] = email
        }
        if let birthDate = birthDate {
            dict["birthDate"] = birthDate.timeIntervalSince1970
        }
        if let gender = gender {
            dict["gender"] = gender.rawValue
        }
        
        return dict
    }
}
