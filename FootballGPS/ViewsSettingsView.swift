//
//  SettingsView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.blue)
                        
                        VStack(alignment: .leading) {
                            Text(MockData.mockUser.displayName)
                                .font(.headline)
                            Text(MockData.mockUser.email ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("プロフィール")
                }
                
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
