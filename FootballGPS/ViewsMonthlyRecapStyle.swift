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

/// 題名の画面から結果の画面への見せ方（§27.9）。画面の切り替え（次へ・前へ）は統一し、
/// 各画面の中のこの見せ方は、中身を表す動きにして変化をつける（Stravaの分析から）
enum RecapRevealStyle {
    /// 横から走り込む（走った距離）
    case runIn
    /// 色の帯が左から伸びて塗る（よく走った日）
    case wipe
    /// 小さな四角が次々に現れて面になる（プレーした日）
    case tiles
    /// 下から昇ってくる（プレーした時間帯）
    case rise
    /// 一瞬で横に駆け抜ける（最速のスプリント）
    case dash
    /// 中心から丸く広がる（一番よかったセッション）
    case spotlight
    /// 左右に割れて上下から合わさる（先月と比べて）
    case split
    /// 大きく拡大してから落ち着く（二つ名）
    case zoom
    /// 上から落ちてきて弾む（獲得したバッジ）
    case drop

    var transition: AnyTransition {
        switch self {
        case .runIn:     return .move(edge: .leading)
        case .wipe:      return .modifier(active: WipeMask(progress: 0), identity: WipeMask(progress: 1))
        case .tiles:     return .modifier(active: TilesMask(progress: 0), identity: TilesMask(progress: 1))
        case .rise:      return .move(edge: .bottom)
        case .dash:      return .move(edge: .trailing)
        case .spotlight: return .modifier(active: CircleMask(progress: 0), identity: CircleMask(progress: 1))
        case .split:     return .modifier(active: SplitReveal(progress: 0), identity: SplitReveal(progress: 1))
        case .zoom:      return .scale(scale: 1.8).combined(with: .opacity)
        case .drop:      return .move(edge: .top)
        }
    }

    var animation: Animation {
        switch self {
        case .dash:  return .easeIn(duration: 0.22)
        case .drop:  return .spring(duration: 0.65, bounce: 0.35)
        case .zoom:  return .spring(duration: 0.55, bounce: 0.2)
        case .tiles: return .easeOut(duration: 0.8)
        case .spotlight: return .easeInOut(duration: 0.65)
        default:     return .easeInOut(duration: 0.5)
        }
    }
}

/// まず単色の画面に項目名だけを出し、約1秒後に結果の画面へ切り替える（Stravaの「TOTAL DISTANCE」→ 数字）。
/// 題名の画面はそのまま下に残し、結果の画面が上に重なる。共有用の画像（animated == false）では、最初から結果の画面を描く
struct TwoBeatSlide<Content: View>: View {
    let title: String
    let titleColor: Color
    var style: RecapRevealStyle = .rise
    let animated: Bool
    @ViewBuilder let content: (_ revealed: Bool) -> Content

    @State private var revealed = false

    var body: some View {
        ZStack {
            if animated {
                ZStack(alignment: .bottomLeading) {
                    titleColor
                    Text(title)
                        .font(.system(size: 30, weight: .heavy))
                        .foregroundStyle(RecapPalette.ink(on: titleColor))
                        .padding(28)
                        .padding(.bottom, 120)
                }
            }
            if revealed || !animated {
                content(true)
                    .transition(style.transition)
            }
        }
        .onAppear {
            guard animated else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(style.animation) { revealed = true }
            }
        }
    }
}

// MARK: - 見せ方のマスク（遷移の途中を progress 0…1 で描く）

/// 左から右へ伸びる帯で見せる
struct WipeMask: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geo in
                Rectangle().frame(width: geo.size.width * progress)
            }
        }
    }
}

/// 中心から広がる円で見せる
struct CircleMask: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func body(content: Content) -> some View {
        content.mask {
            GeometryReader { geo in
                let diameter = hypot(geo.size.width, geo.size.height) * progress
                Circle()
                    .frame(width: diameter, height: diameter)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }
}

/// 小さな四角が、左上から右下へ斜めに順に広がって面になる
struct TilesMask: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    private let cols = 6
    private let rows = 10

    func body(content: Content) -> some View {
        content.mask {
            Canvas { context, size in
                let w = size.width / CGFloat(cols), h = size.height / CGFloat(rows)
                let maxOrder = Double(cols + rows - 2)
                for r in 0..<rows {
                    for c in 0..<cols {
                        // 斜めの順に遅らせて、各四角を 0 → 1 の大きさに広げる
                        let order = Double(r + c) / maxOrder
                        let t = min(1, max(0, (progress - order * 0.5) / 0.5))
                        guard t > 0 else { continue }
                        let rect = CGRect(x: CGFloat(c) * w, y: CGFloat(r) * h, width: w, height: h)
                            .insetBy(dx: w * (1 - t) / 2, dy: h * (1 - t) / 2)
                        context.fill(Path(rect.insetBy(dx: -0.5, dy: -0.5)), with: .color(.black))
                    }
                }
            }
        }
    }
}

/// 左半分は上から、右半分は下から入ってきて合わさる
struct SplitReveal: ViewModifier, Animatable {
    var progress: Double
    var animatableData: Double { get { progress } set { progress = newValue } }

    func body(content: Content) -> some View {
        GeometryReader { geo in
            let shift = geo.size.height * (1 - progress)
            ZStack {
                content
                    .mask(alignment: .leading) { Rectangle().frame(width: geo.size.width / 2) }
                    .offset(y: -shift)
                content
                    .mask(alignment: .trailing) { Rectangle().frame(width: geo.size.width / 2) }
                    .offset(y: shift)
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

// MARK: - 一番走ったセッションの軌跡（走った距離のたとえ）

/// その月で一番走行距離が長かったセッションの軌跡を、ピッチの上に早送りで描いていく。
/// 実際の時間ではなく、決めた秒数で描き終える（§27.9）
struct TrackReplayView: View {
    let track: LongestTrack
    let width: CGFloat
    let startDate: Date
    let animated: Bool

    /// 描き終えるまでの秒数と、描き始めるまでの間（題名の画面の分を含む）
    private let playDuration: Double = 4.0
    private let delay: Double = 1.4

    var body: some View {
        let dimensions = Field.FieldDimensions.standard
        let drawWidth = width - 40
        let drawHeight = drawWidth * CGFloat(dimensions.length / dimensions.width)
        let height = drawHeight + 40
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated)) { context in
            let elapsed = context.date.timeIntervalSince(startDate) - delay
            let progress = animated ? min(1, max(0, elapsed / playDuration)) : 1
            let n = track.path.count
            let headIndex = max(1, Int(progress * Double(n - 1)))
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(RecapPalette.pitch)
                FieldLinesView()
                    .stroke(Color.white.opacity(0.6), lineWidth: 1.2)
                Canvas { gc, _ in
                    func point(_ p: CGPoint) -> CGPoint {
                        // HeatmapGridView と同じ向き（y=0 が下）
                        CGPoint(x: 20 + p.x * drawWidth, y: 20 + (1 - p.y) * drawHeight)
                    }
                    var path = Path()
                    path.addLines(track.path[0...headIndex].map(point))
                    gc.stroke(path, with: .color(RecapPalette.lime.opacity(0.75)),
                              style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    // 描いている先端は光る点（描き終えたら消す）
                    if progress < 1 {
                        let head = point(track.path[headIndex])
                        let dot = CGRect(x: head.x - 5, y: head.y - 5, width: 10, height: 10)
                        gc.fill(Path(ellipseIn: dot.insetBy(dx: -5, dy: -5)), with: .color(RecapPalette.lime.opacity(0.35)))
                        gc.fill(Path(ellipseIn: dot), with: .color(RecapPalette.lime))
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10))  // フィールドの外（ベンチなど）の点がはみ出さないように
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

// MARK: - 現れる演出

enum RecapRevealKind { case rise, pop }

/// 画面に現れたときに、下からふわっと（rise）または弾むように（pop）現れる。
/// 題名→結果の2拍子では、結果の画面が出たときに始まる。共有用の画像では最初から表示する
struct RecapRevealModifier: ViewModifier {
    let animated: Bool
    let delay: Double
    let kind: RecapRevealKind

    @State private var on = false

    func body(content: Content) -> some View {
        let visible = on || !animated
        content
            .opacity(visible ? 1 : 0)
            .scaleEffect(kind == .pop && !visible ? 0.3 : 1)
            .offset(y: kind == .rise && !visible ? 16 : 0)
            .onAppear {
                guard animated else { return }
                let animation: Animation = kind == .pop
                    ? .spring(duration: 0.5, bounce: 0.45).delay(delay)
                    : .easeOut(duration: 0.5).delay(delay)
                withAnimation(animation) { on = true }
            }
    }
}

extension View {
    func reveal(_ animated: Bool, delay: Double = 0, _ kind: RecapRevealKind = .rise) -> some View {
        modifier(RecapRevealModifier(animated: animated, delay: delay, kind: kind))
    }
}

/// 左から伸びる棒（割合 0…1）
struct GrowingBar: View {
    let fraction: Double
    let color: Color
    let animated: Bool
    var delay: Double = 0

    @State private var grown = false

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(color)
                .frame(width: max(4, geo.size.width * CGFloat(min(1, max(0, fraction))) * (grown || !animated ? 1 : 0)))
        }
        .onAppear {
            guard animated else { return }
            withAnimation(.easeOut(duration: 0.7).delay(delay)) { grown = true }
        }
    }
}
