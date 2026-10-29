//
//  ViewsMonthlyRecapStory.swift
//  FootballGPS
//
//  月ごとのまとめのストーリー（技術実装仕様書 §27.3・§27.4）
//

import SwiftUI
import Combine

/// ストーリーの各画面
enum RecapSlide: Hashable {
    case cover, quiz, distance, ranking, calendar, timeOfDay, sprint, best, comparison, style, badges, summary

    /// 新しい見た目（§27.9、平らな単色の面・題名→結果の2拍子）で描く画面。試作のため一部だけ
    var isRedesigned: Bool { [.cover, .distance, .timeOfDay].contains(self) }
}

/// 画面の設計上の大きさ。共有する画像は3倍の 1080×1920px（9:16）
private let slideSize = CGSize(width: 360, height: 640)

// MARK: - ストーリー全体

/// 保存済みのGPSデータを読まずに、ヒートマップやスプリントを渡して再生するための値（開発者ツールのサンプル用）
struct MonthlyRecapPreset {
    let bestGrid: [[Double]]?
    let heatmapFrames: [HeatmapFrame]?
    let sprintReplay: SprintReplay?
}

struct MonthlyRecapStoryView: View {
    let recap: MonthlyRecap
    /// 指定すると、GPSデータの読み込みとAIの二つ名の取得をせずに、この値で再生する
    var preset: MonthlyRecapPreset? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var index = 0
    @State private var progress: Double = 0
    @State private var sharedImage: UIImage?
    @State private var bestGrid: [[Double]]?
    @State private var heatmapFrames: [HeatmapFrame]?
    @State private var sprintReplay: SprintReplay?
    /// クイズで選んだ選択肢（§27.7 C）。答えるまで自動で進まず、画面のタップでも進まない
    @State private var quizAnswer: Int?
    /// 画面の切り替えの向き（次へなら右から、前へなら左から押し出す。§27.9）
    @State private var movingForward = true
    /// その月のセッションに対して作られたAIの二つ名。なければルールで作った二つ名を出す（§27.3）
    @State private var aiNickname: String?

    /// 1画面あたりの秒数。動きを見せる画面（スプリントの再生、積み上がるヒートマップ）は長めにする
    private func slideDuration(_ slide: RecapSlide) -> Double {
        switch slide {
        case .sprint: return 8
        case .calendar: return 6
        case .cover: return 4
        case .distance: return 7     // 題名1秒 → 数字が回り、点がピッチを往復する
        case .timeOfDay: return 6
        case .comparison: return recap.personalBests.isEmpty ? 5 : 7
        case .style:  return (heatmapFrames?.count ?? 0) > 1 ? 9 : 6
        default:      return 5
        }
    }
    private let tick: Double = 0.05
    private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var slides: [RecapSlide] {
        var list: [RecapSlide] = [.cover]
        if recap.quiz != nil { list.append(.quiz) }
        list += [.distance, .ranking, .calendar]
        if recap.timeOfDay != nil { list.append(.timeOfDay) }
        if sprintReplay != nil { list.append(.sprint) }
        list += [.best, .comparison, .style]
        if !recap.newBadges.isEmpty { list.append(.badges) }
        list.append(.summary)
        return list
    }

    private var currentSlide: RecapSlide { slides[index] }

    private var waitingForQuizAnswer: Bool { currentSlide == .quiz && quizAnswer == nil }

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / slideSize.width, geo.size.height / slideSize.height)
            ZStack {
                Color.black.ignoresSafeArea()

                slideView(currentSlide, animated: true)
                    .id(currentSlide)  // 画面が変わるたびに作り直し、演出を最初から再生する
                    .transition(.push(from: movingForward ? .trailing : .leading))
                    .scaleEffect(scale)
                    .frame(width: geo.size.width, height: geo.size.height)

                // 左3分の1で前へ、右3分の2で次へ。クイズに答えるまでは、選択肢をタップできるよう止める
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(width: geo.size.width / 3)
                        .onTapGesture { goBack() }
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { goForward() }
                }
                .allowsHitTesting(!waitingForQuizAnswer)

                VStack {
                    topBar
                    Spacer()
                    shareButton
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .statusBarHidden()
        .onAppear {
            if let preset {
                bestGrid = preset.bestGrid
                heatmapFrames = preset.heatmapFrames
                sprintReplay = preset.sprintReplay
                return
            }
            bestGrid = MonthlyRecapEngine.sessionHeatmap(recap.bestSession, rows: RecapHeatmapView.rows, cols: RecapHeatmapView.cols)
            heatmapFrames = MonthlyRecapEngine.heatmapFrames(recap.sessions, rows: RecapHeatmapView.rows, cols: RecapHeatmapView.cols)
            sprintReplay = MonthlyRecapEngine.fastestSprint(recap.sessions)
        }
        .task {
            guard preset == nil else { return }
            let rows = (try? await SupabaseManager.shared.fetchNicknames(localSessionIds: recap.sessions.map(\.id))) ?? []
            aiNickname = MonthlyRecapEngine.pickNickname(rows, recap: recap)
        }
        .onReceive(timer) { _ in
            // 共有画面を開いているあいだと、最後の画面では自動で進まない
            guard sharedImage == nil, !waitingForQuizAnswer, index < slides.count - 1 else { return }
            progress += tick / slideDuration(currentSlide)
            if progress >= 1 { goForward() }
        }
        .sheet(isPresented: Binding(get: { sharedImage != nil }, set: { if !$0 { sharedImage = nil } })) {
            if let sharedImage {
                ActivityView(items: [sharedImage])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func slideView(_ slide: RecapSlide, animated: Bool) -> some View {
        MonthlyRecapSlideView(
            slide: slide,
            recap: recap,
            bestGrid: bestGrid,
            heatmapFrames: heatmapFrames,
            sprintReplay: sprintReplay,
            quizAnswer: $quizAnswer,
            aiNickname: aiNickname,
            animated: animated
        )
        .frame(width: slideSize.width, height: slideSize.height)
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(slides.indices, id: \.self) { i in
                    GeometryReader { bar in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.3))
                            Capsule().fill(Color.white)
                                .frame(width: bar.size.width * barFill(for: i))
                        }
                    }
                    .frame(height: 3)
                }
            }
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .accessibilityLabel("閉じる")
        }
    }

    private func barFill(for i: Int) -> Double {
        if i < index { return 1 }
        if i > index { return 0 }
        return index == slides.count - 1 ? 1 : progress
    }

    private var shareButton: some View {
        Button {
            sharedImage = renderCurrentSlide()
        } label: {
            Label("この画面を共有・保存", systemImage: "square.and.arrow.up")
                .font(.subheadline.bold())
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.white)
    }

    private func goForward() {
        guard index < slides.count - 1 else { return }
        movingForward = true
        withAnimation(.easeInOut(duration: 0.35)) { index += 1 }
        progress = 0
    }

    private func goBack() {
        movingForward = false
        if index > 0 { withAnimation(.easeInOut(duration: 0.35)) { index -= 1 } }
        progress = 0
    }

    /// 今の画面を演出の終わった状態で 1080×1920px の画像にする
    @MainActor
    private func renderCurrentSlide() -> UIImage? {
        let renderer = ImageRenderer(content: slideView(currentSlide, animated: false))
        renderer.scale = 3
        return renderer.uiImage
    }
}

// MARK: - 各画面

struct MonthlyRecapSlideView: View {
    let slide: RecapSlide
    let recap: MonthlyRecap
    let bestGrid: [[Double]]?
    let heatmapFrames: [HeatmapFrame]?
    let sprintReplay: SprintReplay?
    @Binding var quizAnswer: Int?
    let aiNickname: String?
    /// true なら開いたときに数字が増えるなどの演出をする。共有用の画像では false
    let animated: Bool

    @State private var appeared = false
    /// 動きを見せる画面の再生の起点
    @State private var startDate = Date()

    private var shown: Bool { appeared || !animated }

    var body: some View {
        Group {
            if slide.isRedesigned {
                redesigned
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 56)  // 上部のバーと×の分
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                    footer
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 64)  // 共有ボタンの分
                .background(background)
                .foregroundStyle(.white)
            }
        }
        .frame(width: slideSize.width, height: slideSize.height)
        .clipped()
        .overlay {
            // 自己ベストを更新した月は、画面全体に紙吹雪を降らせる（共有用の画像には描かない）
            if animated && slide == .comparison && !recap.personalBests.isEmpty {
                ConfettiView(startDate: startDate)
                    .allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            startDate = Date()
            guard animated else { return }
            withAnimation(.easeOut(duration: 1.2).delay(0.2)) { appeared = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch slide {
        case .cover: EmptyView()
        case .quiz: quiz
        case .distance, .timeOfDay: EmptyView()  // 新しい見た目（redesigned）で描く
        case .ranking: ranking
        case .calendar: calendar
        case .sprint: sprint
        case .best: best
        case .comparison: comparison
        case .style: style
        case .badges: badges
        case .summary: summary
        }
    }

    private var background: LinearGradient {
        let colors: [Color]
        switch slide {
        case .cover:      colors = [Color(red: 0.05, green: 0.35, blue: 0.20), Color(red: 0.01, green: 0.08, blue: 0.05)]
        case .distance, .ranking, .timeOfDay:
                          colors = [Color(red: 0.05, green: 0.25, blue: 0.45), Color(red: 0.01, green: 0.05, blue: 0.12)]
        case .best:       colors = [Color(red: 0.45, green: 0.20, blue: 0.05), Color(red: 0.12, green: 0.04, blue: 0.01)]
        case .sprint:     colors = [Color(red: 0.50, green: 0.06, blue: 0.10), Color(red: 0.10, green: 0.01, blue: 0.03)]
        case .quiz:       colors = [Color(red: 0.10, green: 0.15, blue: 0.45), Color(red: 0.02, green: 0.03, blue: 0.12)]
        case .calendar:   colors = [Color(red: 0.05, green: 0.30, blue: 0.30), Color(red: 0.01, green: 0.07, blue: 0.08)]
        case .comparison: colors = [Color(red: 0.30, green: 0.10, blue: 0.40), Color(red: 0.07, green: 0.02, blue: 0.10)]
        case .style:      colors = [Color(red: 0.05, green: 0.35, blue: 0.35), Color(red: 0.01, green: 0.08, blue: 0.08)]
        case .badges:     colors = [Color(red: 0.45, green: 0.35, blue: 0.05), Color(red: 0.12, green: 0.08, blue: 0.01)]
        case .summary:    colors = [Color(red: 0.05, green: 0.30, blue: 0.18), Color(red: 0.01, green: 0.05, blue: 0.04)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("FootballGPS")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(recap.month.fullTitle)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
        }
    }

    private var nickname: String {
        aiNickname ?? MonthlyRecapEngine.ruleNickname(position: recap.topPosition, playerType: recap.topPlayerType)
    }

    // MARK: 表紙

    private var cover: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(String(recap.month.year))
                .font(.system(size: 18, weight: .semibold))
                .opacity(0.7)
            Text("\(recap.month.title)の\nサッカー")
                .font(.system(size: 52, weight: .heavy))
                .lineSpacing(-4)
                .scaleEffect(shown ? 1 : 0.9, anchor: .leading)
                .opacity(shown ? 1 : 0)
            HStack(spacing: 24) {
                bigNumber(Double(recap.sessionCount), unit: "回", label: "プレーした回数", format: "%.0f")
                VStack(alignment: .leading, spacing: 2) {
                    Text("プレー時間")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.7)
                    Text(Self.durationText(recap.totalDuration))
                        .font(.system(size: 26, weight: .bold))
                }
            }
            .opacity(shown ? 1 : 0)
        }
        .padding(.top, 60)
    }

    // MARK: 走った量

    private var distance: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(recap.month.title)に走った距離")
                .font(.system(size: 20, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(String(format: "%.1f", shown ? recap.totalDistance / 1000 : 0))
                    .font(.system(size: 64, weight: .heavy).monospacedDigit())
                    .contentTransition(.numericText(value: shown ? recap.totalDistance : 0))
                Text("km")
                    .font(.system(size: 26, weight: .bold))
            }
            Text(String(format: "1回あたり %.2f km ・ スプリント合計 %d 回", recap.totalDistance / 1000 / Double(recap.sessionCount), recap.totalSprints))
                .font(.system(size: 15, weight: .medium))
                .opacity(shown ? 0.85 : 0)
            Label(Self.equivalentText(recap.totalDistance), systemImage: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(.yellow)
                .opacity(shown ? 1 : 0)
            distanceRanking
                .padding(.top, 6)
        }
        .padding(.top, 8)
    }

    /// よく走った日（新しい見た目の「走った距離」から分けた画面。§27.9）
    private var ranking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(recap.month.title)によく走った日")
                .font(.system(size: 24, weight: .heavy))
            distanceRanking
        }
        .padding(.top, 20)
    }

    /// 走行距離が多かった日（同じ日のセッションは合計。上位10日まで。§27.3）
    private var distanceRanking: some View {
        let days = recap.dailyDistances
        let top = days.prefix(10)
        let maxDistance = top.first?.distance ?? 1
        return VStack(alignment: .leading, spacing: 7) {
            Text(top.count < days.count ? "よく走った日 ベスト\(top.count)" : "よく走った日")
                .font(.system(size: 13, weight: .bold))
                .opacity(0.8)
            ForEach(Array(top.enumerated()), id: \.offset) { rank, day in
                HStack(spacing: 8) {
                    Text("\(rank + 1)")
                        .font(.system(size: 11, weight: .heavy).monospacedDigit())
                        .frame(width: 18, height: 18)
                        .background(Color.white.opacity(rank == 0 ? 0.35 : 0.15), in: Circle())
                    Text(Self.dayText(day.day))
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 92, alignment: .leading)
                    GeometryReader { bar in
                        Capsule()
                            .fill(Color.white.opacity(rank == 0 ? 0.9 : 0.6))
                            .frame(width: bar.size.width * (shown ? day.distance / maxDistance : 0), height: 5)
                            .frame(maxHeight: .infinity)
                    }
                    Text(String(format: "%.2f km", day.distance / 1000))
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                        .frame(width: 62, alignment: .trailing)
                }
                .frame(height: 18)
                .opacity(shown ? 1 : 0)
                .animation(animated ? .easeOut(duration: 0.5).delay(0.3 + Double(rank) * 0.08) : nil, value: shown)
            }
        }
    }

    // MARK: 新しい見た目の画面（§27.9）

    @ViewBuilder
    private var redesigned: some View {
        switch slide {
        case .cover: newCover
        case .distance: newDistance
        case .timeOfDay: newTimeOfDay
        default: EmptyView()
        }
    }

    /// 新しい見た目の画面の下端（アイコン・名前・月）。文字の色を背景に合わせる
    private func newFooter(ink: Color) -> some View {
        HStack(spacing: 8) {
            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Text("FootballGPS")
                .font(.system(size: 13, weight: .bold))
            Spacer()
            Text(recap.month.fullTitle)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 28)
        .padding(.bottom, 72)  // 共有ボタンの分
    }

    /// 季節の言葉。厳しい季節は「それでも」とつなぐ
    private var seasonLine: String {
        let m = recap.month.month
        let days = recap.playedDays.count
        switch m {
        case 7, 8:  return "暑い\(m)月。\nそれでも\(days)日、\nピッチに立った。"
        case 12, 1, 2: return "寒い\(m)月。\nそれでも\(days)日、\nピッチに立った。"
        case 6:     return "雨の多い\(m)月。\nそれでも\(days)日、\nピッチに立った。"
        case 3, 4, 5: return "春の\(m)月。\n\(days)日、\nピッチに立った。"
        default:    return "秋の\(m)月。\n\(days)日、\nピッチに立った。"
        }
    }

    private var newCover: some View {
        let bg = RecapPalette.orange
        let ink = RecapPalette.ink(on: bg)
        return ZStack(alignment: .topLeading) {
            bg
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 70)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    RollingNumberText(text: "\(recap.month.month)", size: 190, animated: animated)
                    Text("月")
                        .font(.system(size: 48, weight: .heavy))
                }
                .offset(x: -6)
                Text(seasonLine)
                    .font(.system(size: 30, weight: .heavy))
                    .lineSpacing(2)
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : 20)
                Spacer()
            }
            .padding(.horizontal, 28)
            .foregroundStyle(ink)
            VStack { Spacer(); newFooter(ink: ink) }
        }
    }

    private var newDistance: some View {
        TwoBeatSlide(title: "\(recap.month.title)に\n走った距離は…", titleColor: RecapPalette.navy, animated: animated) { _ in
            let bg = RecapPalette.lime
            let ink = RecapPalette.ink(on: bg)
            ZStack(alignment: .top) {
                bg
                VStack(alignment: .leading, spacing: 0) {
                    RecapHeaderStrip(title: "走った距離", color: RecapPalette.navy)
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            RollingNumberText(text: String(format: "%.1f", recap.totalDistance / 1000), size: 96, animated: animated)
                            Text("km")
                                .font(.system(size: 30, weight: .heavy))
                        }
                        HStack(alignment: .bottom, spacing: 18) {
                            PitchRoundTripView(width: 110, startDate: startDate, animated: animated)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("ピッチ")
                                    .font(.system(size: 18, weight: .bold))
                                RollingNumberText(text: "\(Int(recap.totalDistance / 210))", size: 48, animated: animated)
                                Text("往復分。")
                                    .font(.system(size: 22, weight: .heavy))
                            }
                        }
                        Text(Self.marathonText(recap.totalDistance) + String(format: " ・ 1回あたり %.2f km", recap.totalDistance / 1000 / Double(recap.sessionCount)))
                            .font(.system(size: 13, weight: .semibold))
                            .opacity(0.75)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    Spacer()
                    newFooter(ink: ink)
                }
                .foregroundStyle(ink)
            }
        }
    }

    @ViewBuilder
    private var newTimeOfDay: some View {
        if let time = recap.timeOfDay {
            TwoBeatSlide(title: "いつ、\nプレーしていた？", titleColor: RecapPalette.orange, animated: animated) { _ in
                let bg = time.band.slideColor
                let ink = RecapPalette.ink(on: bg)
                ZStack(alignment: .top) {
                    bg
                    VStack(alignment: .leading, spacing: 0) {
                        RecapHeaderStrip(title: "よくプレーした時間帯", color: RecapPalette.orange)
                        VStack(alignment: .leading, spacing: 16) {
                            TimeOfDaySkyView(band: time.band, width: 304, animated: animated)
                            Text(String(format: "%d:00–%d:00", time.peakHour, (time.peakHour + 1) % 24))
                                .font(.system(size: 44, weight: .heavy).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text(time.band.line)
                                .font(.system(size: 22, weight: .heavy))
                                .opacity(shown ? 1 : 0)
                            hourChart(time, ink: ink)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 20)
                        Spacer()
                        newFooter(ink: ink)
                    }
                    .foregroundStyle(ink)
                }
            }
        }
    }

    /// 0〜23時の開始回数の棒（最も多い時間帯を強調）
    private func hourChart(_ time: RecapTimeOfDay, ink: Color) -> some View {
        let maxCount = max(time.hourCounts.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    let count = time.hourCounts[hour]
                    RoundedRectangle(cornerRadius: 2)
                        .fill(RecapTimeBand.band(forHour: hour) == time.band ? RecapPalette.orange : ink.opacity(0.25))
                        .frame(height: count == 0 ? 2 : 40 * CGFloat(count) / CGFloat(maxCount))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 40, alignment: .bottom)
            HStack {
                Text("0時"); Spacer(); Text("6時"); Spacer(); Text("12時"); Spacer(); Text("18時"); Spacer(); Text("24時")
            }
            .font(.system(size: 10, weight: .medium))
            .opacity(0.6)
        }
    }

    static func marathonText(_ meters: Double) -> String {
        let marathons = meters / 42_195
        return marathons >= 1 ? String(format: "フルマラソン約%.1f回分", marathons) : "フルマラソンの約\(Int(marathons * 100))%"
    }

    // MARK: クイズ（§27.7 C）

    @ViewBuilder
    private var quiz: some View {
        if let quiz = recap.quiz {
            VStack(alignment: .leading, spacing: 18) {
                Text("クイズ")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.2), in: Capsule())
                Text("\(recap.month.title)、一番たくさん\n走った日はどれ？")
                    .font(.system(size: 30, weight: .heavy))
                ForEach(quiz.options.indices, id: \.self) { i in
                    quizOption(quiz, index: i)
                }
                if let answer = quizAnswer {
                    Text(answer == quiz.correctIndex ? "正解！" : "残念！正解は \(Self.dayText(quiz.options[quiz.correctIndex].day))")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(answer == quiz.correctIndex ? .green : .orange)
                    Text("画面をタップして次へ")
                        .font(.system(size: 13))
                        .opacity(0.7)
                } else {
                    Text("選択肢をタップして答えてください")
                        .font(.system(size: 13))
                        .opacity(0.7)
                }
            }
            .padding(.top, 30)
        }
    }

    private func quizOption(_ quiz: RecapQuiz, index: Int) -> some View {
        let option = quiz.options[index]
        let answered = quizAnswer != nil
        let isCorrect = index == quiz.correctIndex
        let isChosen = quizAnswer == index
        return Button {
            guard quizAnswer == nil else { return }
            withAnimation(.spring(duration: 0.4)) { quizAnswer = index }
        } label: {
            HStack {
                Text(Self.dayText(option.day))
                    .font(.system(size: 18, weight: .bold))
                Spacer()
                if answered {
                    Text(String(format: "%.2f km", option.distance / 1000))
                        .font(.system(size: 16, weight: .bold).monospacedDigit())
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : (isChosen ? "xmark.circle.fill" : "circle"))
                        .foregroundStyle(isCorrect ? .green : (isChosen ? .orange : .white.opacity(0.4)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(answered && isCorrect ? Color.green.opacity(0.3) : Color.white.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isChosen ? Color.white : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        // 答えた後も選択肢を暗くしないよう、disabled ではなく action の中で2回目のタップを無視する
    }

    // MARK: 活動カレンダーと継続（§27.7 E）

    private var calendar: some View {
        let cal = Calendar.current
        let start = recap.month.start()
        let daysInMonth = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        // 月曜始まり: 1日の曜日（日曜=1）から、前に空ける数を求める
        let leading = (cal.component(.weekday, from: start) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 14) {
            Text("\(recap.month.title)にプレーした日")
                .font(.system(size: 20, weight: .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(recap.playedDays.count)")
                    .font(.system(size: 56, weight: .heavy).monospacedDigit())
                Text("日")
                    .font(.system(size: 22, weight: .bold))
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { label in
                    Text(label)
                        .font(.system(size: 11, weight: .bold))
                        .opacity(0.6)
                }
                ForEach(0..<(leading + daysInMonth), id: \.self) { cell in
                    let day = cell - leading + 1
                    if day < 1 {
                        Color.clear.frame(height: 32)
                    } else {
                        let played = recap.playedDays.contains(day)
                        Text("\(day)")
                            .font(.system(size: 13, weight: played ? .heavy : .regular).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(
                                Circle()
                                    .fill(played ? Color.green : Color.white.opacity(0.06))
                                    .scaleEffect(played && shown ? 1 : (played ? 0.2 : 1))
                            )
                            .opacity(played || shown ? 1 : 0.4)
                            .animation(animated ? .spring(duration: 0.5).delay(0.3 + Double(day) * 0.03) : nil, value: shown)
                    }
                }
            }
            if recap.weeklyStreak >= 2 {
                Label("\(recap.weeklyStreak)週連続でプレー", systemImage: "flame.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.orange)
                    .opacity(shown ? 1 : 0)
            }
        }
        .padding(.top, 20)
    }

    // MARK: 自己ベスト（§27.7 F）

    private var personalBestBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("自己ベスト更新！", systemImage: "trophy.fill")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(.yellow)
            ForEach(recap.personalBests, id: \.title) { best in
                HStack {
                    Text(best.title)
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.8)
                    Spacer()
                    Text("\(best.previous) → ")
                        .font(.system(size: 13).monospacedDigit())
                        .opacity(0.7)
                    Text(best.value)
                        .font(.system(size: 16, weight: .heavy).monospacedDigit())
                }
            }
        }
        .padding(14)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .scaleEffect(shown ? 1 : 0.8)
        .opacity(shown ? 1 : 0)
    }

    // MARK: 最速のスプリント（§27.7 A）

    @ViewBuilder
    private var sprint: some View {
        if let replay = sprintReplay {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(recap.month.title)最速のスプリント")
                    .font(.system(size: 20, weight: .semibold))
                Text(Self.dayText(replay.date))
                    .font(.system(size: 15, weight: .medium))
                    .opacity(0.8)
                SprintReplayView(replay: replay, width: 220, startDate: startDate, animated: animated)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                Text(String(format: "距離 %.0f m ・ %.1f 秒", replay.distance, replay.duration))
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.85)
                    .frame(maxWidth: .infinity)
            }
            .padding(.top, 4)
        }
    }

    // MARK: 一番よかったセッション

    private var best: some View {
        let session = recap.bestSession
        return VStack(alignment: .leading, spacing: 14) {
            Text("一番よかったセッション")
                .font(.system(size: 20, weight: .semibold))
            Text(Self.dayText(session.date))
                .font(.system(size: 34, weight: .heavy))
            HStack(alignment: .top, spacing: 16) {
                if let bestGrid {
                    RecapHeatmapView(grid: bestGrid, width: 130)
                        .opacity(shown ? 1 : 0)
                        .scaleEffect(shown ? 1 : 0.92)
                }
                VStack(alignment: .leading, spacing: 12) {
                    smallStat("走行距離", String(format: "%.2f km", session.totalDistance / 1000))
                    smallStat(
                        session.isLowGPSAccuracy ? "最高速度（参考値）" : "最高速度",
                        String(format: "%.1f km/h", session.maxSpeed * 3.6)
                    )
                    smallStat("スプリント", "\(session.sprintCount ?? 0) 回")
                    smallStat("総合スコア", "\(recap.bestSessionScore) 点")
                }
            }
        }
        .padding(.top, 20)
    }

    // MARK: 先月と比べて

    private var comparison: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("先月と比べて")
                .font(.system(size: 34, weight: .heavy))
            if recap.hasComparison {
                if let change = recap.distancePerMinute {
                    changeRow("1分あたりの走行距離", change: change) { String(format: "%.0f m", $0) }
                }
                if let change = recap.maxSpeed {
                    changeRow("最高速度", change: change) { String(format: "%.1f km/h", $0 * 3.6) }
                }
                if let change = recap.sprintsPerSession {
                    changeRow("1回あたりのスプリント", change: change) { String(format: "%.1f 回", $0) }
                }
                Text("±5%以内は「維持」としています")
                    .font(.system(size: 12))
                    .opacity(0.6)
                if !recap.personalBests.isEmpty {
                    personalBestBox
                }
            } else {
                Text("先月の記録がないため比べられません。来月は今月と比べられます")
                    .font(.system(size: 17, weight: .medium))
                    .opacity(0.85)
            }
        }
        .padding(.top, 50)
    }

    private func changeRow(_ title: String, change: RecapMetricChange, format: (Double) -> String) -> some View {
        let (symbol, text, color): (String, String, Color) = {
            switch change.direction {
            case .up:   return ("arrow.up.right", "伸びた", .green)
            case .kept: return ("arrow.right", "維持", .cyan)
            case .down: return ("arrow.down.right", "下がった", .orange)
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .opacity(0.75)
            HStack(spacing: 10) {
                Text("\(format(change.previous)) → \(format(change.current))")
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Label(text, systemImage: symbol)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(color)
                    .fixedSize()
                    .opacity(shown ? 1 : 0)
            }
        }
    }

    // MARK: 今月のあなた

    private var style: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(recap.month.title)のあなたの二つ名")
                .font(.system(size: 18, weight: .semibold))
            Text(nickname)
                .font(.system(size: 38, weight: .heavy))
                .lineLimit(1)  // 言葉の途中で改行しないよう、1行に収まるまで小さくする
                .minimumScaleFactor(0.45)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.9, anchor: .leading)
            HStack(spacing: 8) {
                chip("タイプ: \(recap.topPlayerType.rawValue)")
                if let position = recap.topPosition {
                    chip("ポジション: \(position.displayName)")
                }
            }
            if let frames = heatmapFrames, !frames.isEmpty {
                AccumulatingHeatmapView(
                    frames: frames, month: recap.month, width: 170,
                    startDate: startDate, animated: animated
                )
                .padding(.top, 6)
            }
        }
        .padding(.top, 10)
    }

    // MARK: 獲得したバッジ

    private var badges: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(recap.month.title)に獲得したバッジ")
                .font(.system(size: 26, weight: .heavy))
            ForEach(Array(recap.newBadges.prefix(6).enumerated()), id: \.offset) { offset, badge in
                HStack(spacing: 14) {
                    Image(systemName: badge.sfSymbol)
                        .font(.system(size: 24))
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(badge.name)
                            .font(.system(size: 17, weight: .bold))
                        if let tier = badge.tier {
                            Text(tier.displayName)
                                .font(.system(size: 13, weight: .medium))
                                .opacity(0.75)
                        }
                    }
                }
                .opacity(shown ? 1 : 0)
                .offset(x: shown ? 0 : -12)
                .animation(animated ? .easeOut(duration: 0.5).delay(0.2 + Double(offset) * 0.15) : nil, value: shown)
            }
            if recap.newBadges.count > 6 {
                Text("ほか \(recap.newBadges.count - 6) 個")
                    .font(.system(size: 14, weight: .medium))
                    .opacity(0.75)
            }
        }
        .padding(.top, 40)
    }

    // MARK: まとめ

    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(recap.month.title)のまとめ")
                .font(.system(size: 34, weight: .heavy))
            Text(nickname)
                .font(.system(size: 22, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.18), in: Capsule())
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 18) {
                smallStat("回数", "\(recap.sessionCount) 回")
                smallStat("プレー時間", Self.durationText(recap.totalDuration))
                smallStat("走行距離", String(format: "%.1f km", recap.totalDistance / 1000))
                smallStat("スプリント", "\(recap.totalSprints) 回")
                if let speed = recap.bestMaxSpeed {
                    smallStat("最高速度", String(format: "%.1f km/h", speed * 3.6))
                }
                if let position = recap.topPosition {
                    smallStat("主なポジション", position.displayName)
                }
                smallStat("プレイヤータイプ", recap.topPlayerType.rawValue)
            }
        }
        .padding(.top, 40)
    }

    // MARK: 部品

    private func bigNumber(_ value: Double, unit: String, label: String, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: format, shown ? value : 0))
                    .font(.system(size: 40, weight: .heavy).monospacedDigit())
                    .contentTransition(.numericText(value: shown ? value : 0))
                Text(unit)
                    .font(.system(size: 16, weight: .bold))
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2), in: Capsule())
    }

    private func smallStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.7)
            Text(value)
                .font(.system(size: 22, weight: .bold).monospacedDigit())
        }
    }

    /// 走行距離を身近なものに置き換える（§27.7 D）。ピッチ（105m）の往復と、フルマラソン（42.195km）
    static func equivalentText(_ meters: Double) -> String {
        let pitchRoundTrips = Int(meters / 210)
        let marathons = meters / 42_195
        let marathonText = marathons >= 1
            ? String(format: "フルマラソン約%.1f回分", marathons)
            : "フルマラソンの約\(Int(marathons * 100))%"
        return "ピッチ約\(pitchRoundTrips)往復 ・ \(marathonText)"
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分"
    }

    static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日（E）"
        return formatter.string(from: date)
    }
}

// MARK: - ヒートマップ（フィールドの寸法は標準の 105×68m で描く）

struct RecapHeatmapView: View {
    static let rows = 28
    static let cols = 40

    let grid: [[Double]]
    let width: CGFloat

    var body: some View {
        // FieldBackgroundView・HeatmapGridView はどちらも外周20ptの内側にフィールドを描く
        let dimensions = Field.FieldDimensions.standard
        let drawWidth = width - 40
        let height = drawWidth * CGFloat(dimensions.length / dimensions.width) + 40
        return ZStack {
            FieldBackgroundView()
            HeatmapGridView(
                heatmap: grid,
                rows: Self.rows,
                cols: Self.cols,
                size: CGSize(width: width, height: height),
                dimensions: dimensions
            )
            .blur(radius: 5)
        }
        .frame(width: width, height: height)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - 最速のスプリントの再生（§27.7 A）

/// ピッチの上で、その月で一番速かったスプリントを点が走る動きで再生する。速度の表示も点に合わせて変わる
struct SprintReplayView: View {
    let replay: SprintReplay
    let width: CGFloat
    let startDate: Date
    /// false なら再生の終わった状態で描く（共有用の画像）
    let animated: Bool

    /// 再生にかける秒数。実際の時間（数秒）に近く、短すぎないようにする
    private var playDuration: Double { min(5, max(3, replay.duration + 1.5)) }
    /// 再生を始めるまでの間
    private let delay: Double = 0.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animated)) { context in
            let elapsed = context.date.timeIntervalSince(startDate) - delay
            let progress = animated ? min(1, max(0, elapsed / playDuration)) : 1
            content(progress: progress)
        }
    }

    private func content(progress: Double) -> some View {
        let dimensions = Field.FieldDimensions.standard
        let drawWidth = width - 40
        let drawHeight = drawWidth * CGFloat(dimensions.length / dimensions.width)
        let height = drawHeight + 40
        let n = replay.path.count
        let position = progress * Double(n - 1)
        let index = min(n - 1, Int(position))
        let speed = progress >= 1 ? replay.maxSpeed : replay.speeds[index]

        func point(_ p: CGPoint) -> CGPoint {
            // HeatmapGridView と同じ向き（y=0 が下）
            CGPoint(x: 20 + p.x * drawWidth, y: 20 + (1 - p.y) * drawHeight)
        }
        let current: CGPoint = {
            guard index + 1 < n else { return point(replay.path[n - 1]) }
            let a = point(replay.path[index]), b = point(replay.path[index + 1])
            let t = position - Double(index)
            return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }()

        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("時速")
                    .font(.system(size: 16, weight: .bold))
                Text(String(format: "%.1f", speed * 3.6))
                    .font(.system(size: 54, weight: .heavy).monospacedDigit())
                Text("km")
                    .font(.system(size: 18, weight: .bold))
            }
            ZStack {
                FieldBackgroundView()
                Canvas { context, _ in
                    // 全体の軌跡はうっすら、走った部分は濃く描く（助走は白、スプリント区間は赤）
                    var whole = Path()
                    whole.addLines(replay.path.map(point))
                    context.stroke(whole, with: .color(.white.opacity(0.2)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    guard index >= 0 else { return }
                    for i in 0..<max(0, index) + (index + 1 < n ? 1 : 0) {
                        guard i + 1 < n else { break }
                        let a = point(replay.path[i])
                        let b = i == index ? current : point(replay.path[i + 1])
                        var segment = Path()
                        segment.move(to: a)
                        segment.addLine(to: b)
                        let inSprint = i >= replay.sprintStart && i < replay.sprintEnd
                        context.stroke(
                            segment,
                            with: .color(inSprint ? Color(red: 1, green: 0.3, blue: 0.25) : .white.opacity(0.8)),
                            style: StrokeStyle(lineWidth: inSprint ? 4 : 2.5, lineCap: .round)
                        )
                    }
                    let dot = CGRect(x: current.x - 6, y: current.y - 6, width: 12, height: 12)
                    context.fill(Path(ellipseIn: dot.insetBy(dx: -5, dy: -5)), with: .color(.white.opacity(0.25)))
                    context.fill(Path(ellipseIn: dot), with: .color(.white))
                }
            }
            .frame(width: width, height: height)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - 日ごとに積み上がるヒートマップ（§27.7 B）

/// プレーした日ごとにヒートマップを重ねていき、ピッチが少しずつ色づいていく様子を見せる
struct AccumulatingHeatmapView: View {
    let frames: [HeatmapFrame]
    let month: RecapMonth
    let width: CGFloat
    let startDate: Date
    let animated: Bool

    /// 1コマを見せる秒数。日数が多くても4秒ほどで積み上がるようにする
    private var step: Double { min(0.7, 4.0 / Double(max(frames.count, 1))) }
    private let delay: Double = 0.8

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated)) { context in
            let elapsed = context.date.timeIntervalSince(startDate) - delay
            let index = animated ? min(frames.count - 1, max(0, Int(elapsed / step))) : frames.count - 1
            HStack(alignment: .bottom, spacing: 12) {
                RecapHeatmapView(grid: frames[index].grid, width: width)
                VStack(alignment: .leading, spacing: 4) {
                    Text(index == frames.count - 1 ? "\(month.title)のすべて" : Self.dayText(frames[index].day) + "まで")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                    Text("\(index + 1) / \(frames.count) 日")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.75)
                    Text("プレーした日ごとに\n重ねたヒートマップ")
                        .font(.system(size: 12, weight: .medium))
                        .opacity(0.75)
                        .padding(.top, 6)
                }
            }
        }
    }

    private static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - 紙吹雪（§27.7 F）

/// 自己ベストの更新を祝う紙吹雪。上から舞い落ちて消える。共有用の画像には描かない
struct ConfettiView: View {
    let startDate: Date
    private let count = 36
    private let duration: Double = 2.6
    private let delay: Double = 0.4
    private let colors: [Color] = [.yellow, .orange, .green, .cyan, .pink, .white]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = (context.date.timeIntervalSince(startDate) - delay) / duration
            Canvas { gc, size in
                guard t > 0, t < 1 else { return }
                for i in 0..<count {
                    // 番号から決まる疑似乱数（毎回同じ動き）
                    func r(_ k: Double) -> Double { abs(sin(Double(i) * 12.9898 + k * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1) }
                    let x = r(1) * size.width + sin(t * 6 + r(2) * 6) * 12
                    let y = -20 + (size.height + 60) * t * (0.7 + r(3) * 0.6)
                    let angle = Angle.degrees(t * 720 * (r(4) - 0.5))
                    var piece = gc
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: angle)
                    piece.opacity = 1 - t
                    piece.fill(Path(CGRect(x: -3, y: -5, width: 6, height: 10)), with: .color(colors[i % colors.count]))
                }
            }
        }
    }
}
