//
//  ViewsShareCard.swift
//  FootballGPS
//
//  セッションの結果カードを画像にして共有する（技術実装仕様書 §26）
//

import SwiftUI

/// 結果カードに載せる値。セッション詳細で計算済みの値を渡す
struct ShareCardData {
    let date: Date
    let position: PlayingPosition?
    let playerType: PlayerType
    /// プロスタイル診断で最も近いスタイルと一致率。診断できないときは nil
    let proStyle: (name: String, syncRate: Double)?
    let totalDistance: Double   // m
    let maxSpeed: Double        // m/s
    let sprintCount: Int
    let duration: TimeInterval
    let averageHeartRate: Double?
}

enum ShareCardBackground: String, CaseIterable, Identifiable {
    case normal = "通常"
    case transparent = "透明"
    var id: String { rawValue }
}

/// 共有する画像そのもの（360×450pt、3倍で 1080×1350px の4:5）
struct ShareCardView: View {
    static let size = CGSize(width: 360, height: 450)

    let data: ShareCardData
    let gpsData: GPSData
    let field: Field
    let isFlipped: Bool
    let background: ShareCardBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(alignment: .top, spacing: 14) {
                heatmap
                stats
            }
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(width: Self.size.width, height: Self.size.height)
        .background {
            if background == .normal {
                LinearGradient(
                    colors: [Color(red: 0.05, green: 0.30, blue: 0.18), Color(red: 0.02, green: 0.08, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .foregroundStyle(.white)
        // 透明の背景では写真の上に重ねるため、どんな色の上でも読めるよう影を付ける
        .shadow(color: .black.opacity(background == .transparent ? 0.7 : 0), radius: 2)
        .environment(\.colorScheme, .dark)
    }

    /// ヒートマップ。FieldHeatmapView はフィールドの図の外側を背景色で塗るため、
    /// 枠をフィールドの縦横比ぴったりにして、背景色（透明の背景では黒い四角になる）が見えないようにする
    private var heatmap: some View {
        // FieldHeatmapView の内側の寸法: フィールドの図＋左右・上下20ptずつの縁
        let margin: CGFloat = 40
        let maxWidth: CGFloat = 160
        let maxHeight: CGFloat = 270
        let ratio = CGFloat(field.dimensions.width / field.dimensions.length)
        var innerWidth = maxWidth
        var innerHeight = (innerWidth - margin) / ratio + margin
        if innerHeight > maxHeight {
            innerHeight = maxHeight
            innerWidth = (innerHeight - margin) * ratio + margin
        }
        // FieldHeatmapView 自身の外側の余白（.padding() の16pt）を打ち消す
        return FieldHeatmapView(gpsData: gpsData, field: field, isFlipped: isFlipped)
            .frame(width: innerWidth + 32, height: innerHeight + 32)
            .padding(-16)
            .frame(width: innerWidth, height: innerHeight)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(Self.dateText(data.date))
                    .font(.system(size: 12, weight: .medium))
                    .opacity(0.8)
                if let position = data.position {
                    Text(position.displayName)
                        .font(.system(size: 11, weight: .bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
            }
            Text(data.playerType.rawValue)
                .font(.system(size: 30, weight: .heavy))
            if let proStyle = data.proStyle {
                Text("プロスタイル: \(proStyle.name) \(Int(proStyle.syncRate))%")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.9)
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 10) {
            statRow(label: "走行距離", value: String(format: "%.2f", data.totalDistance / 1000), unit: "km")
            statRow(label: "最高速度", value: String(format: "%.1f", data.maxSpeed * 3.6), unit: "km/h")
            statRow(label: "スプリント", value: "\(data.sprintCount)", unit: "回")
            statRow(label: "プレー時間", value: "\(Int(data.duration / 60))", unit: "分")
            if let bpm = data.averageHeartRate {
                statRow(label: "平均心拍", value: String(format: "%.0f", bpm), unit: "bpm")
            }
        }
    }

    private func statRow(label: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.75)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 26, weight: .bold).monospacedDigit())
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.85)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            // アプリのアイコン（起動画面と同じ画像）。iOSのアイコンと同じ角丸にする
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5.4, style: .continuous))
            Text("FootballGPS")
                .font(.system(size: 14, weight: .bold))
            Spacer()
        }
        .opacity(0.9)
    }
}

/// iOS標準の共有画面。ShareLink に PNG のデータを渡す方式では「画像を保存」が出ず、Instagram でも
/// 「コンテンツを利用できません」となったため、UIImage を UIActivityViewController に直接渡す（§26.3）
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// カードのプレビューと共有
struct ShareCardSheet: View {
    let data: ShareCardData
    let gpsData: GPSData
    let field: Field
    let isFlipped: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var background: ShareCardBackground = .normal
    /// PNG のデータから作り直した画像（透明の背景の透過を保つ）
    @State private var rendered: UIImage?
    @State private var showingActivity = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                cardPreview
                    .scaleEffect(0.85)
                    .frame(width: ShareCardView.size.width * 0.85, height: ShareCardView.size.height * 0.85)

                Picker("背景", selection: $background) {
                    ForEach(ShareCardBackground.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if background == .transparent {
                    Text("透明の背景は、InstagramやLINEで自分の写真の上に重ねるときに使えます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if rendered != nil {
                    Button {
                        showingActivity = true
                    } label: {
                        Label("共有・保存", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                }
                Spacer()
            }
            .padding(.top)
            .navigationTitle("結果を共有")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
            .onAppear { render() }
            .onChange(of: background) { _, _ in render() }
            .sheet(isPresented: $showingActivity) {
                if let rendered {
                    // 画像だけを渡す（文章を一緒に渡すと受け付けない共有先があるため）
                    ActivityView(items: [rendered])
                        .presentationDetents([.medium, .large])
                }
            }
        }
    }

    /// 画面上のプレビュー。透明の背景は市松模様の上に置いて透けていることを示す
    private var cardPreview: some View {
        ShareCardView(data: data, gpsData: gpsData, field: field, isFlipped: isFlipped, background: background)
            .background {
                if background == .transparent {
                    Canvas { context, size in
                        let cell: CGFloat = 12
                        for row in 0..<Int(size.height / cell) + 1 {
                            for col in 0..<Int(size.width / cell) + 1 where (row + col).isMultiple(of: 2) {
                                context.fill(
                                    Path(CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)),
                                    with: .color(.gray.opacity(0.3))
                                )
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(radius: 6)
    }

    @MainActor
    private func render() {
        let renderer = ImageRenderer(
            content: ShareCardView(data: data, gpsData: gpsData, field: field, isFlipped: isFlipped, background: background)
        )
        renderer.scale = 3
        renderer.isOpaque = background == .normal
        // PNG を経由して作り直すことで、透明の背景の透過を保った画像にする
        guard let png = renderer.uiImage?.pngData(), let image = UIImage(data: png) else {
            rendered = nil
            return
        }
        rendered = image
    }
}
