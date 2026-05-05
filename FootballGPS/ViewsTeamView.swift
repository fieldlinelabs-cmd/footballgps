//
//  TeamView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

struct TeamView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                
                Text("チーム機能")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("ステップ3で実装予定")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("チーム")
        }
    }
}

#Preview {
    TeamView()
}
