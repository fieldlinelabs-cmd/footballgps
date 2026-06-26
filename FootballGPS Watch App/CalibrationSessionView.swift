//
//  CalibrationSessionView.swift
//  FootballGPS Watch App
//
#if DEBUG
import SwiftUI
import CoreMotion

private class CalibrationRecorder: ObservableObject {
    private let motion = CMMotionManager()
    private(set) var samples: [CalibrationSample] = []
    @Published var sampleCount = 0
    @Published var elapsed: TimeInterval = 0
    private var startDate = Date()
    private var displayTimer: Timer?

    func beginRecording() {
        samples = []
        sampleCount = 0
        elapsed = 0
        startDate = Date()

        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 50.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
                guard let self, let m else { return }
                self.samples.append(CalibrationSample(
                    timestamp: Date().timeIntervalSince(self.startDate),
                    tag: "",
                    accX: m.userAcceleration.x,
                    accY: m.userAcceleration.y,
                    accZ: m.userAcceleration.z,
                    gyroX: m.rotationRate.x,
                    gyroY: m.rotationRate.y,
                    gyroZ: m.rotationRate.z,
                    speed: 0.0
                ))
                self.sampleCount = self.samples.count
            }
        }

        displayTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = Date().timeIntervalSince(self.startDate)
        }
    }

    func stopRecording() -> [CalibrationSample] {
        motion.stopDeviceMotionUpdates()
        displayTimer?.invalidate()
        displayTimer = nil
        return samples
    }
}

struct CalibrationSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = CalibrationRecorder()

    private enum Phase {
        case idle
        case recording
        case done(String)
    }

    @State private var phase: Phase = .idle

    var body: some View {
        phaseView
            .onAppear {
                WatchConnectivityService.shared.cleanupCalibrationTempFiles()
            }
    }

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .idle:
            idleView
        case .recording:
            recordingView
        case .done(let message):
            doneView(message: message)
        }
    }

    // MARK: - Phase Views

    private var idleView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path")
                .font(.system(size: 36))
                .foregroundStyle(.blue)
            Text("キャリブレーション")
                .font(.headline)
            Text("動作を行い終了ボタンを押します")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("開始") {
                recorder.beginRecording()
                phase = .recording
            }
            .buttonStyle(.borderedProminent)
            Button("キャンセル") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding()
    }

    private var recordingView: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
            Text(formatElapsed(recorder.elapsed))
                .font(.system(size: 36, weight: .bold, design: .monospaced))
                .foregroundStyle(.red)
            Text("\(recorder.sampleCount) samples")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button("終了") {
                stopAndTransfer()
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
    }

    private func doneView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: message.hasPrefix("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(message.hasPrefix("✅") ? Color.green : Color.red)
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.center)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Helpers

    private func stopAndTransfer() {
        let samples = recorder.stopRecording()
        let csv = buildCSV(samples)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "calib_\(formatter.string(from: Date())).csv"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        do {
            try csv.write(to: tempURL, atomically: true, encoding: .utf8)
            WatchConnectivityService.shared.transferCalibrationFile(url: tempURL, filename: filename)
            phase = .done("✅ 転送キューに追加しました\n(\(samples.count) samples)")
        } catch {
            phase = .done("❌ 書き込み失敗: \(error.localizedDescription)")
        }
    }

    private func buildCSV(_ samples: [CalibrationSample]) -> String {
        var lines = ["timestamp,accX,accY,accZ"]
        for s in samples {
            lines.append(String(
                format: "%.4f,%.6f,%.6f,%.6f",
                s.timestamp,
                s.accX, s.accY, s.accZ
            ))
        }
        return lines.joined(separator: "\n")
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
#endif
