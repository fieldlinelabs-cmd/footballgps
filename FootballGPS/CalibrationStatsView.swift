//
//  CalibrationStatsView.swift
//  FootballGPS
//

#if DEBUG
import SwiftUI

struct CalibrationStatsView: View {
    @State private var stats: [SupabaseManager.AgeGroupStats] = []
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                ProgressView("集計中...")
            } else if stats.isEmpty {
                Text("データがありません")
                    .foregroundStyle(.secondary)
            } else {
                Section("スプリント最高速度（中央値）") {
                    ForEach(stats) { s in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(s.ageGroup) \(s.gender)")
                                    .font(.subheadline)
                                Text("n=\(s.count)  P25=\(String(format: "%.1f", s.p25SpeedKmh))  P75=\(String(format: "%.1f", s.p75SpeedKmh))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f km/h", s.medianSpeedKmh))
                                .font(.title3)
                                .fontWeight(.bold)
                        }
                    }
                }

                if stats.contains(where: { $0.medianAgilityG != nil }) {
                    Section("アジリティピーク（中央値）") {
                        ForEach(stats.filter { $0.medianAgilityG != nil }) { s in
                            HStack {
                                Text("\(s.ageGroup) \(s.gender)")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.1fG", s.medianAgilityG!))
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("閾値集計")
        .task { await fetchStats() }
    }

    private func fetchStats() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await SupabaseManager.shared.fetchCalibrationStats()
        } catch {
            print("⚠️ 集計取得失敗: \(error)")
        }
    }
}
#endif
