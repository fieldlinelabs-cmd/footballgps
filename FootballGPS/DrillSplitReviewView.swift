//
//  DrillSplitReviewView.swift
//  FootballGPS
//
//  ドリル自動分割（休憩の自動検知）で検出された分割候補を、コーチが確認・確定するための画面。
//  トリム機能の確認ダイアログと同じ思想: 何が起きるかを見せてから、確定するかどうかを選ばせる。
//

import SwiftUI

struct DrillSplitReviewView: View {
    let session: TrainingSession

    @ObservedObject private var dataManager = SessionDataManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isConfirming = false

    private var breaks: [DrillBreakInterval] {
        session.pendingSplitBreaks ?? []
    }

    private var ranges: [(start: TimeInterval, end: TimeInterval)] {
        DrillSplitDetector.segmentRanges(totalDuration: session.duration, breaks: breaks)
    }

    private var gpsData: GPSData? {
        dataManager.getGPSData(for: session.id)
    }

    /// analyzeForDrillSplitsと同じ解決順序: fieldIdがあればそれを、なければ一致率で自動判定にフォールバック
    private var field: Field? {
        if let fieldId = session.fieldId {
            return FieldManager.shared.getField(by: fieldId)
        }
        guard let gpsData else { return nil }
        return FieldManager.shared.detectField(for: gpsData.points)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("休憩を自動検知し、\(ranges.count)本のドリルへの分割を提案します。内容を確認してから確定してください。分割前の記録はいつでも復元できます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let gpsData, let field {
                    Section {
                        DrillSplitFieldMapView(
                            gpsData: gpsData,
                            field: field,
                            isFlipped: session.isFlipped,
                            ranges: ranges,
                            breaks: breaks
                        )
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                Section("検出されたドリル") {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                        HStack {
                            Circle()
                                .fill(DrillSplitFieldMapView.segmentColors[index % DrillSplitFieldMapView.segmentColors.count])
                                .frame(width: 10, height: 10)
                            Text("ドリル\(index + 1)")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(formatRange(range))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("ドリル分割の確認")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    Button {
                        isConfirming = true
                        Task {
                            await dataManager.confirmDrillSplit(for: session.id)
                            isConfirming = false
                            dismiss()
                        }
                    } label: {
                        Text("この分割を確定する")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isConfirming || ranges.count < 2)

                    Button("分割せず1本のまま残す") {
                        dataManager.dismissPendingSplit(for: session.id)
                        dismiss()
                    }
                    .font(.subheadline)
                    .disabled(isConfirming)
                }
                .padding()
                .background(.bar)
            }
            .overlay {
                if isConfirming {
                    ProgressView("分割を確定中…")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func formatRange(_ range: (start: TimeInterval, end: TimeInterval)) -> String {
        let duration = range.end - range.start
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let startTime = session.date.addingTimeInterval(range.start)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return "\(formatter.string(from: startTime))〜 (\(minutes)分\(seconds)秒)"
    }
}
