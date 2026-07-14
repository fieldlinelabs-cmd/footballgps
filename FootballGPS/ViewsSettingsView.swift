//
//  SettingsView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import PhotosUI
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @ObservedObject private var profileManager = UserProfileManager.shared
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            List {
                Section("プロフィール") {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                avatarView
                            }
                            if profileManager.profile.avatarImageData != nil {
                                Button("写真を削除", role: .destructive) {
                                    profileManager.removeAvatarImage()
                                }
                                .font(.caption)
                            }
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            guard let newItem,
                                  let data = try? await newItem.loadTransferable(type: Data.self),
                                  let uiImage = UIImage(data: data) else { return }
                            profileManager.setAvatarImage(uiImage)
                        }
                    }

                    HStack {
                        Text("名前")
                        Spacer()
                        TextField("未設定", text: $profileManager.profile.displayName)
                            .multilineTextAlignment(.trailing)
                    }

                    DatePicker(
                        "生年月日",
                        selection: Binding(
                            get: { profileManager.profile.birthDate ?? Date() },
                            set: { profileManager.profile.birthDate = $0 }
                        ),
                        displayedComponents: .date
                    )

                    Picker("性別", selection: $profileManager.profile.gender) {
                        Text("未設定").tag(Gender?.none)
                        ForEach(Gender.allCases, id: \.self) { g in
                            Text(g.displayName).tag(Gender?.some(g))
                        }
                    }

                    Picker("選手カテゴリ", selection: $profileManager.profile.playerCategory) {
                        Text("未設定").tag(PlayerCategory?.none)
                        ForEach(PlayerCategory.allCases, id: \.self) { c in
                            Text(c.displayName).tag(PlayerCategory?.some(c))
                        }
                    }
                    Text("「プレイヤーデータ」タブの累計系バッジの難易度に使われます。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .onChange(of: profileManager.profile.displayName) { _, _ in profileManager.save() }
                .onChange(of: profileManager.profile.birthDate) { _, _ in profileManager.save() }
                .onChange(of: profileManager.profile.gender) { _, _ in profileManager.save() }
                .onChange(of: profileManager.profile.playerCategory) { _, _ in profileManager.save() }
                
                Section {
                    NavigationLink {
                        Text("フィールド管理（ステップ2で実装）")
                    } label: {
                        Label("フィールド管理", systemImage: "map.fill")
                    }
                    
                    NavigationLink {
                        Text("通知設定")
                    } label: {
                        Label("通知", systemImage: "bell.fill")
                    }
                } header: {
                    Text("設定")
                }
                
                Section {
                    Link(destination: URL(string: "https://example.com")!) {
                        Label("ヘルプ", systemImage: "questionmark.circle.fill")
                    }
                    
                    Link(destination: URL(string: "https://example.com")!) {
                        Label("プライバシーポリシー", systemImage: "hand.raised.fill")
                    }
                } header: {
                    Text("サポート")
                }
                
                Section {
                    Toggle(isOn: Binding(
                        get: { dataManager.isICloudBackupEnabled },
                        set: { dataManager.setICloudBackupEnabled($0) }
                    )) {
                        Label("iCloudバックアップ", systemImage: "icloud.fill")
                    }
                    Text("GPSデータをiCloudにバックアップします。オフの場合、バックアップ容量を節約できます（デフォルト: オフ）。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("データ")
                }

                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let data = profileManager.profile.avatarImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 88, height: 88)
        .clipShape(Circle())
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(6)
                .background(Color.accentColor)
                .clipShape(Circle())
        }
    }
}

#Preview {
    SettingsView()
}
