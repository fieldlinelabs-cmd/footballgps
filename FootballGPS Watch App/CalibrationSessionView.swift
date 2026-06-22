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
        case pickingTag([CalibrationSample])
        case done(String)
    }

    @State private var phase: Phase = .idle

    private let tags = ["急停止", "急加速", "切り返し", "ターン", "反転", "バックペダル"]

    var body: some View {
        phaseView
    }

    @ViewBuilder
    private var phaseView: some View {
        switch phase {
        case .idle:
            idleView
        case .recording:
            recordingView
        case .pickingTag(let samples):
            tagPickerView(samples: samples)
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
            Text("動作後に種類を選択します")
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
                let captured = recorder.stopRecording()
                phase = .pickingTag(captured)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
    }

    private func tagPickerView(samples: [CalibrationSample]) -> some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("動作を選択")
                    .font(.headline)
                    .padding(.bottom, 4)
                ForEach(tags, id: \.self) { tag in
                    Button(tag) {
                        transferCSV(samples: samples, tag: tag)
                    }
                    .buttonStyle(.bordered)
                }
                Button("キャンセル") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .padding()
        }
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

    private func transferCSV(samples: [CalibrationSample], tag: String) {
        let tagged = samples.map {
            CalibrationSample(
                timestamp: $0.timestamp, tag: tag,
                accX: $0.accX, accY: $0.accY, accZ: $0.accZ,
                gyroX: $0.gyroX, gyroY: $0.gyroY, gyroZ: $0.gyroZ,
                speed: $0.speed
            )
        }
        let csv = buildCSV(tagged)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "calib_\(tag)_\(formatter.string(from: Date())).csv"
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
        var lines = ["timestamp,tag,accX,accY,accZ,gyroX,gyroY,gyroZ,speed"]
        for s in samples {
            lines.append(String(
                format: "%.4f,%@,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.4f",
                s.timestamp, s.tag,
                s.accX, s.accY, s.accZ,
                s.gyroX, s.gyroY, s.gyroZ,
                s.speed
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
