//
//  SettingsView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @ObservedObject private var profileManager = UserProfileManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("プロフィール") {
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
                }
                .onChange(of: profileManager.profile.displayName) { _, _ in profileManager.save() }
                .onChange(of: profileManager.profile.birthDate) { _, _ in profileManager.save() }
                .onChange(of: profileManager.profile.gender) { _, _ in profileManager.save() }
                
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
}

#Preview {
    SettingsView()
}
