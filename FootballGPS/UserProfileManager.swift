//
//  UserProfileManager.swift
//  FootballGPS
//

import Foundation
import Combine

class UserProfileManager: ObservableObject {
    static let shared = UserProfileManager()

    @Published var profile: UserProfile

    private let key = "userProfile"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = saved
        } else {
            profile = UserProfile(
                id: UUID().uuidString,
                displayName: ""
            )
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    /// 年齢を計算（birthDate 未設定時は nil）
    var age: Int? {
        guard let birthDate = profile.birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Supabase匿名認証後にIDを同期する
    func syncId(with authUid: String) {
        guard profile.id != authUid else { return }
        let savedBirthDate = profile.birthDate
        let savedGender = profile.gender
        profile = UserProfile(
            id: authUid,
            displayName: profile.displayName,
            email: profile.email,
            teamIds: profile.teamIds,
            createdAt: profile.createdAt
        )
        profile.birthDate = savedBirthDate
        profile.gender = savedGender
        save()
    }
}
