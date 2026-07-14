//
//  UserProfileManager.swift
//  FootballGPS
//

import Foundation
import Combine
import UIKit

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
        let savedAvatarImageData = profile.avatarImageData
        let savedPlayerCategory = profile.playerCategory
        let savedTeamName = profile.teamName
        let savedTeamEmblemImageData = profile.teamEmblemImageData
        profile = UserProfile(
            id: authUid,
            displayName: profile.displayName,
            email: profile.email,
            teamIds: profile.teamIds,
            createdAt: profile.createdAt
        )
        profile.birthDate = savedBirthDate
        profile.gender = savedGender
        profile.avatarImageData = savedAvatarImageData
        profile.playerCategory = savedPlayerCategory
        profile.teamName = savedTeamName
        profile.teamEmblemImageData = savedTeamEmblemImageData
        save()
    }

    /// 画像を最大512pxにリサイズ・JPEG圧縮してプロフィールに設定する
    func setAvatarImage(_ image: UIImage) {
        profile.avatarImageData = image.resizedForAvatar(maxDimension: 512).jpegData(compressionQuality: 0.7)
        save()
    }

    func removeAvatarImage() {
        profile.avatarImageData = nil
        save()
    }

    /// 画像を最大512pxにリサイズ・JPEG圧縮してチームエンブレムに設定する
    func setTeamEmblemImage(_ image: UIImage) {
        profile.teamEmblemImageData = image.resizedForAvatar(maxDimension: 512).jpegData(compressionQuality: 0.7)
        save()
    }

    func removeTeamEmblemImage() {
        profile.teamEmblemImageData = nil
        save()
    }
}

private extension UIImage {
    func resizedForAvatar(maxDimension: CGFloat) -> UIImage {
        let scale = min(maxDimension / size.width, maxDimension / size.height, 1.0)
        guard scale < 1.0 else { return self }
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
