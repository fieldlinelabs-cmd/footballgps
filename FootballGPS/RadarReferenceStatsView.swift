//
//  RadarReferenceStatsView.swift
//  FootballGPS
//

#if DEBUG
import SwiftUI

/// レーダーチャートのMax定数（SessionDataManager.computePlayerRadar）を見直すための参考画面。
/// ここに表示される値はアプリには反映されず、開発者が見てコードの定数を手動で調整する。
struct RadarReferenceStatsView: View {
    @State private var stats: SupabaseManager.RadarReferenceStats?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private struct Row: Identifiable {
        let id = UUID()
        let label: String
        let unit: String
        let currentMax: Double
        let percentiles: SupabaseManager.Percentiles
    }

    private var rows: [Row] {
        guard let stats else { return [] }
        return [
            Row(label: "走力", unit: "m/分", currentMax: 130, percentiles: stats.distance),
            Row(label: "スプリント", unit: "回/分", currentMax: 1.0, percentiles: stats.sprint),
            Row(label: "アジリティ", unit: "回/分", currentMax: 4.5, percentiles: stats.agility),
            Row(label: "高強度（自己指標、Max=100固定）", unit: "%", currentMax: 100, percentiles: stats.hrIntensity),
            Row(label: "最高速度", unit: "km/h", currentMax: 28.8, percentiles: kmhPercentiles(stats.maxSpeed))
        ]
    }

    /// m/s単位のPercentilesをkm/h表示用に変換する（速度表示は全画面km/hに統一）
    private func kmhPercentiles(_ p: SupabaseManager.Percentiles) -> SupabaseManager.Percentiles {
        SupabaseManager.Percentiles(
            p50: p.p50.map { $0 * 3.6 },
            p75: p.p75.map { $0 * 3.6 },
            p90: p.p90.map { $0 * 3.6 }
        )
    }

    var body: some View {
        List {
            if isLoading {
                ProgressView("集計中...")
            } else if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else if let stats {
                Section {
                    Text("対象セッション数（5分以上）: n=\(stats.n)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("サンプル数")
                }

                ForEach(rows) { row in
                    Section(row.label) {
                        HStack {
                            Text("現在のMax定数")
                            Spacer()
                            Text("\(format(row.currentMax)) \(row.unit)")
                                .fontWeight(.bold)
                        }
                        percentileRow(label: "P50（中央値）", value: row.percentiles.p50, unit: row.unit)
                        percentileRow(label: "P75", value: row.percentiles.p75, unit: row.unit)
                        percentileRow(label: "P90", value: row.percentiles.p90, unit: row.unit)
                    }
                }
            } else {
                Text("データがありません")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("レーダーMax参考集計")
        .task { await fetchStats() }
    }

    private func percentileRow(label: String, value: Double?, unit: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            if let value {
                Text("\(format(value)) \(unit)")
            } else {
                Text("--")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private func format(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func fetchStats() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await SupabaseManager.shared.fetchRadarReferenceStats()
        } catch {
            errorMessage = "集計取得失敗: \(error.localizedDescription)"
        }
    }
}
#endif
