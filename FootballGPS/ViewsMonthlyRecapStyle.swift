//
//  ViewsMonthlyRecapStyle.swift
//  FootballGPS
//
//  月ごとのまとめの新しい見た目の部品（技術実装仕様書 §27.9、Stravaの年間まとめを参考にした試作）。
//  平らな単色の面、大きな数字、「題名の画面 → 結果」の2拍子、回る数字、サッカーの「たとえ」の絵
//

import SwiftUI

// MARK: - 色の決まり

/// FootballGPSのまとめの色。グラデーションではなく、はっきりした単色の面で使う
enum RecapPalette {
    static let pitch  = Color(red: 0.10, green: 0.42, blue: 0.24)   // 芝の緑
    static let lime   = Color(red: 0.86, green: 0.93, blue: 0.28)   // ライム
    static let orange = Color(red: 1.00, green: 0.45, blue: 0.13)   // オレンジ
    static let navy   = Color(red: 0.07, green: 0.11, blue: 0.33)   // 紺
    static let lilac  = Color(red: 0.86, green: 0.78, blue: 0.96)   // 薄紫
    static let cream  = Color(red: 0.97, green: 0.95, blue: 0.90)   // 生成り

    /// 明るい色の上では黒、暗い色の上では白の文字にする
    static func ink(on color: Color) -> Color {
        [lime, lilac, cream, orange].contains(color) ? Color(red: 0.08, green: 0.08, blue: 0.10) : .white
    }
}

// MARK: - 題名 → 結果の2拍子

/// まず単色の画面に項目名だけを出し、約1秒後に結果の画面へ切り替える（Stravaの「TOTAL DISTANCE」→ 数字）。
/// 共有用の画像（animated == false）では、最初から結果の画面を描く
struct TwoBeatSlide<Content: View>: View {
    let title: String
    let titleColor: Color
    let animated: Bool
    @ViewBuilder let content: (_ revealed: Bool) -> Content

    @State private var revealed = false

    var body: some View {
        ZStack {
            if revealed || !animated {
                content(true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ZStack(alignment: .bottomLeading) {
                    titleColor
                    Text(title)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(RecapPalette.ink(on: titleColor))
                        .padding(28)
                        .padding(.bottom, 120)
                }
                .transition(.move(edge: .top))
            }
        }
        .onAppear {
            guard animated else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeInOut(duration: 0.45)) { revealed = true }
            }
        }
    }
}

/// 結果の画面の上部に出す、項目名の帯（Stravaの「TOTAL DAYS ACTIVE」のオレンジの帯）
struct RecapHeaderStrip: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .heavy))
            .tracking(1)
            .foregroundStyle(RecapPalette.ink(on: color))
            .padding(.horizontal, 28)
            .padding(.top, 58)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color)
    }
}

// MARK: - 回る数字

/// 走行距離計のように、けたごとに数字が回って止まる。数字以外の文字（. , など）はそのまま出す
struct RollingNumberText: View {
    let text: String
    let size: CGFloat
    let animated: Bool
    var weight: Font.Weight = .heavy

    @State private var rolled = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                if let digit = char.wholeNumberValue {
                    digitColumn(digit, index: index)
                } else {
                    Text(String(char))
                        .font(.system(size: size, weight: weight))
                }
            }
        }
        .onAppear {
            guard animated else { return }
            rolled = true
        }
    }

    private func digitColumn(_ digit: Int, index: Int) -> some View {
        let height = size * 1.2
        // 1周回してから目的の数字に止める
        let target = rolled || !animated ? digit + 10 : 0
        return VStack(spacing: 0) {
            ForEach(0..<20, id: \.self) { n in
                Text("\(n % 10)")
                    .font(.system(size: size, weight: weight).monospacedDigit())
                    .frame(height: height)
            }
        }
        .offset(y: -CGFloat(target) * height)
        .frame(height: height, alignment: .top)
        .clipped()
        .animation(animated ? .spring(duration: 1.1, bounce: 0.15).delay(0.15 + Double(index) * 0.08) : nil, value: rolled)
    }
}

// MARK: - ピッチの往復（走行距離のたとえ）

/// 縦向きのピッチの上を、点がゴールからゴールへ何度も往復する（Stravaの「陸上トラックを点が走る」をサッカーに）
struct PitchRoundTripView: View {
    let width: CGFloat
    let startDate: Date
    let animated: Bool

    /// 見せる往復の回数と、1往復の秒数
    private let laps = 3
    private let lapDuration: Double = 1.1
    private let delay: Double = 1.4

    var body: some View {
        let height = width * 1.5
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated)) { context in
            let elapsed = context.date.timeIntervalSince(startDate) - delay
            let total = Double(laps) * lapDuration
            let t = animated ? min(total, max(0, elapsed)) : total
            // 0→1→0 を往復ごとに繰り返す
            let phase = (t / lapDuration).truncatingRemainder(dividingBy: 1)
            let y = phase < 0.5 ? phase * 2 : (1 - phase) * 2
            let margin: CGFloat = 18
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(RecapPalette.pitch)
                FieldLinesView()
                    .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                // 走った跡（縦の線）
                Capsule()
                    .fill(RecapPalette.lime.opacity(0.35))
                    .frame(width: 6, height: height - margin * 2 - 4)
                Circle()
                    .fill(RecapPalette.lime)
                    .frame(width: 16, height: 16)
                    .shadow(color: RecapPalette.lime.opacity(0.8), radius: 8)
                    .position(x: width / 2, y: margin + 2 + (height - margin * 2 - 4) * (t >= total ? 0 : y))
            }
            .frame(width: width, height: height)
        }
    }
}

// MARK: - プレーした時間帯の空

/// 時間帯に合わせた空と、昇る太陽（または月）。朝・昼・夕方・夜で色と天体が変わる
struct TimeOfDaySkyView: View {
    let band: RecapTimeBand
    let width: CGFloat
    let animated: Bool

    @State private var risen = false

    var body: some View {
        let height = width * 0.62
        ZStack(alignment: .bottom) {
            Rectangle().fill(band.skyColor)
            Circle()
                .fill(band.celestialColor)
                .frame(width: width * 0.62, height: width * 0.62)
                .offset(y: risen || !animated ? width * 0.31 : width * 0.62)
            Rectangle()
                .fill(RecapPalette.pitch)
                .frame(height: 10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.6).delay(1.3)) { risen = true }
        }
    }
}

extension RecapTimeBand {
    var skyColor: Color {
        switch self {
        case .morning: return Color(red: 0.99, green: 0.80, blue: 0.55)
        case .daytime: return Color(red: 0.55, green: 0.80, blue: 0.98)
        case .evening: return Color(red: 0.98, green: 0.52, blue: 0.35)
        case .night:   return Color(red: 0.07, green: 0.10, blue: 0.28)
        }
    }

    var celestialColor: Color {
        switch self {
        case .morning, .daytime: return Color(red: 1.0, green: 0.88, blue: 0.20)
        case .evening:           return Color(red: 1.0, green: 0.70, blue: 0.20)
        case .night:             return Color(red: 0.95, green: 0.95, blue: 0.85)
        }
    }

    /// 結果の画面の背景（単色）
    var slideColor: Color {
        switch self {
        case .morning: return RecapPalette.cream
        case .daytime: return RecapPalette.cream
        case .evening: return RecapPalette.lilac
        case .night:   return RecapPalette.navy
        }
    }
}
