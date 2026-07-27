//
//  SprintMeasurementView.swift
//  FootballGPS
//

#if DEBUG
import SwiftUI

struct SprintMeasurementView: View {
    @ObservedObject private var dataManager = SessionDataManager.shared
    @State private var sessionResults: [(name: String, date: Date, maxSpeed: Double, maxSpeedKmh: Double)] = []
    @State private var showAlert = false
    @State private var alertMessage = ""

    var body: some View {
        List {
            Section {
                Text("各セッションの最高GPS速度")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("スプリント最高速度") {
                if sessionResults.isEmpty {
                    Text("セッションがありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sessionResults, id: \.name) { r in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(r.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(r.date, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text(String(format: "%.1f km/h", r.maxSpeedKmh))
                                    .font(.title3)
                                    .fontWeight(.bold)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                Task { await uploadResult(r) }
                            } label: {
                                Label("アップロード", systemImage: "icloud.and.arrow.up")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .navigationTitle("計測データ")
        .onAppear { loadSessions() }
        .alert("アップロード", isPresented: $showAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func loadSessions() {
        sessionResults = dataManager.sessions.compactMap { session in
            guard let gpsData = dataManager.getEffectiveGPSData(for: session) else { return nil }
            let maxSpeed = gpsData.points.map(\.speed).max() ?? 0
            guard maxSpeed * 3.6 >= 8.0 else { return nil }
            return (session.name, session.date, maxSpeed, maxSpeed * 3.6)
        }
        .sorted { $0.date > $1.date }
    }

    private func uploadResult(_ result: (name: String, date: Date, maxSpeed: Double, maxSpeedKmh: Double)) async {
        let pm = UserProfileManager.shared
        do {
            try await SupabaseManager.shared.uploadCalibrationResult(
                age: pm.age,
                gender: pm.profile.gender,
                maxSpeed: result.maxSpeed,
                agilityPeakG: nil,
                agilityEventCount: nil
            )
            alertMessage = "✓ \(result.name) の最高速度 \(String(format: "%.1f km/h", result.maxSpeedKmh)) をアップロードしました"
        } catch {
            alertMessage = "✗ アップロード失敗: \(error.localizedDescription)"
        }
        showAlert = true
    }
}
#endif
