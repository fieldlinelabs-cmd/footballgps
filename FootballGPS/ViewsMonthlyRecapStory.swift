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
}

/// 画面の設計上の大きさ。共有する画像は3倍の 1080×1920px（9:16）
private let slideSize = CGSize(width: 360, height: 640)

// MARK: - ストーリー全体

/// 保存済みのGPSデータを読まずに、ヒートマップやスプリントを渡して再生するための値（開発者ツールのサンプル用）
struct MonthlyRecapPreset {
    let bestGrid: [[Double]]?
    let heatmapFrames: [HeatmapFrame]?
    let sprintReplay: SprintReplay?
    var longestTrack: LongestTrack? = nil
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
    @State private var longestTrack: LongestTrack?
    /// クイズで選んだ選択肢（§27.7 C）。答えるまで自動で進まず、画面のタップでも進まない
    @State private var quizAnswer: Int?
    /// 画面の切り替えの向き（次へなら右から、前へなら左から押し出す。§27.9）
    @State private var movingForward = true
    /// その月のセッションに対して作られたAIの二つ名。なければルールで作った二つ名を出す（§27.3）
    @State private var aiNickname: String?

    /// 1画面あたりの秒数（§27.9）。**動きが止まってから pauseAfterMotion 秒**で次へ進み、**最短でも5秒**にする。
    /// 表紙は文を読む時間を残して4秒、クイズは答えてから2秒（問いは答える前に読んでいる）
    private func slideDuration(_ slide: RecapSlide) -> Double {
        switch slide {
        case .cover: return 4
        case .quiz: return 2
        case .summary: return 5   // 最後の画面なので自動では進まない
        default:
            var seconds = motionEnd(slide) + Self.pauseAfterMotion
            if slide == .comparison { seconds = max(5, seconds) }  // 数字を3組読む時間
            return max(Self.minimumSlideDuration, seconds)
        }
    }

    /// 動きが止まってから次へ進むまでの秒数（1秒では速く、3秒では最初の長さに戻るため2秒にした）
    static let pauseAfterMotion: Double = 2
    /// 最短の秒数。3秒では情報量に関係なくテンポが速すぎ、4秒でも「一番よかったセッション」が短く感じたため5秒にした
    static let minimumSlideDuration: Double = 5

    /// 画面を開いてから動きが止まるまでの秒数（題名の画面の約1秒を含む）
    private func motionEnd(_ slide: RecapSlide) -> Double {
        switch slide {
        case .distance: return 5.4      // 軌跡を描き終わる
        case .ranking: return 2.9       // 棒が伸び終わる
        case .calendar: return 3.5      // 丸と「○週連続」が出終わる
        case .timeOfDay: return 3.9     // 太陽が昇り終わる
        case .sprint:
            // 題名1秒 ＋ 再生前の間 ＋ 再生（スプリントの長さで変わる）
            return sprintReplay.map { 1.0 + SprintReplayView.delay + SprintReplayView.playDuration(for: $0) } ?? 2
        case .best: return 2.0          // ヒートマップと数値が出る
        case .comparison:
            return recap.personalBests.isEmpty ? 3.0 : 4.2  // 棒と矢印が出る／紙吹雪が終わる
        case .style:
            // 題名1秒 ＋ 積み上げ前の間 ＋ 最後のコマが出るまで（日数で変わる）
            let frames = heatmapFrames?.count ?? 0
            guard frames > 1 else { return 1.7 }
            return 1.0 + AccumulatingHeatmapView.delay + Double(frames - 1) * AccumulatingHeatmapView.step(frameCount: frames)
        case .badges: return 2.8        // バッジが出終わる
        case .cover, .quiz, .summary: return 0
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
                longestTrack = preset.longestTrack
                return
            }
            bestGrid = MonthlyRecapEngine.sessionHeatmap(recap.bestSession, rows: RecapHeatmapView.rows, cols: RecapHeatmapView.cols)
            heatmapFrames = MonthlyRecapEngine.heatmapFrames(recap.sessions, rows: RecapHeatmapView.rows, cols: RecapHeatmapView.cols)
            sprintReplay = MonthlyRecapEngine.fastestSprint(recap.sessions)
            longestTrack = MonthlyRecapEngine.longestTrack(recap.sessions)
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
            longestTrack: longestTrack,
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
    let longestTrack: LongestTrack?
    @Binding var quizAnswer: Int?
    let aiNickname: String?
    /// true なら開いたときに数字が回るなどの演出をする。共有用の画像では false
    let animated: Bool

    @State private var appeared = false
    /// 動きを見せる画面の再生の起点
    @State private var startDate = Date()

    private var shown: Bool { appeared || !animated }

    var body: some View {
        redesigned
            .frame(width: slideSize.width, height: slideSize.height)
            .clipped()
            .overlay {
                // 自己ベストを更新した月は、画面全体に紙吹雪を降らせる（共有用の画像には描かない）
                if animated && slide == .comparison && !recap.personalBests.isEmpty {
                    ConfettiView(startDate: startDate.addingTimeInterval(1.2))
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

    private var nickname: String {
        aiNickname ?? MonthlyRecapEngine.ruleNickname(position: recap.topPosition, playerType: recap.topPlayerType)
    }

    // MARK: 新しい見た目の画面（§27.9）

    @ViewBuilder
    private var redesigned: some View {
        switch slide {
        case .cover: newCover
        case .quiz: newQuiz
        case .distance: newDistance
        case .ranking: newRanking
        case .calendar: newCalendar
        case .timeOfDay: newTimeOfDay
        case .sprint: newSprint
        case .best: newBest
        case .comparison: newComparison
        case .style: newStyle
        case .badges: newBadges
        case .summary: newSummary
        }
    }

    /// 結果の画面の共通の枠: 単色の背景、上部の帯、本文、下端（§27.9）
    private func page<Body: View>(
        _ header: String, headerColor: Color, background bg: Color,
        @ViewBuilder body: @escaping (_ ink: Color) -> Body
    ) -> some View {
        let ink = RecapPalette.ink(on: bg)
        return ZStack(alignment: .top) {
            bg
            VStack(alignment: .leading, spacing: 0) {
                RecapHeaderStrip(title: header, color: headerColor)
                body(ink)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
                newFooter(ink: ink)
            }
            .foregroundStyle(ink)
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
        TwoBeatSlide(title: "\(recap.month.title)に\n走った距離は…", titleColor: RecapPalette.navy, style: .runIn, animated: animated) { _ in
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
                            // 一番走ったセッションの軌跡を早送りで描く。フィールドの登録がなければ、ピッチを往復する点
                            if let track = longestTrack {
                                VStack(alignment: .leading, spacing: 4) {
                                    TrackReplayView(track: track, width: 124, startDate: startDate, animated: animated)
                                    Text("一番走った日 \(Self.shortDay(track.date))")
                                        .font(.system(size: 10, weight: .bold))
                                        .opacity(0.7)
                                }
                            } else {
                                PitchRoundTripView(width: 110, startDate: startDate, animated: animated)
                            }
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
            TwoBeatSlide(title: "いつ、\nプレーしていた？", titleColor: RecapPalette.orange, style: .rise, animated: animated) { _ in
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
    private var newQuiz: some View {
        if let quiz = recap.quiz {
            page("クイズ", headerColor: RecapPalette.orange, background: RecapPalette.navy) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    Text("\(recap.month.title)、一番たくさん\n走った日はどれ？")
                        .font(.system(size: 30, weight: .heavy))
                        .padding(.bottom, 6)
                    ForEach(quiz.options.indices, id: \.self) { i in
                        quizOption(quiz, index: i)
                    }
                    if let answer = quizAnswer {
                        Text(answer == quiz.correctIndex ? "正解！" : "残念！正解は \(Self.dayText(quiz.options[quiz.correctIndex].day))")
                            .font(.system(size: 24, weight: .heavy))
                            .foregroundStyle(answer == quiz.correctIndex ? RecapPalette.lime : RecapPalette.orange)
                            .transition(.scale.combined(with: .opacity))
                        Text("画面をタップして次へ")
                            .font(.system(size: 13))
                            .opacity(0.7)
                    } else {
                        Text("選択肢をタップして答えてください")
                            .font(.system(size: 13))
                            .opacity(0.7)
                    }
                }
            }
        }
    }

    private func quizOption(_ quiz: RecapQuiz, index: Int) -> some View {
        let option = quiz.options[index]
        let answered = quizAnswer != nil
        let isCorrect = index == quiz.correctIndex
        let isChosen = quizAnswer == index
        let fill: Color = !answered ? Color.white.opacity(0.12)
            : isCorrect ? RecapPalette.lime
            : isChosen ? RecapPalette.orange : Color.white.opacity(0.06)
        let ink: Color = answered && (isCorrect || isChosen) ? RecapPalette.ink(on: RecapPalette.lime) : .white
        return Button {
            // 答えた後も選択肢を暗くしないよう、disabled ではなくここで2回目のタップを無視する
            guard quizAnswer == nil else { return }
            withAnimation(.spring(duration: 0.4)) { quizAnswer = index }
        } label: {
            HStack {
                Text(Self.dayText(option.day))
                    .font(.system(size: 20, weight: .heavy))
                Spacer()
                if answered {
                    Text(String(format: "%.2f km", option.distance / 1000))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : (isChosen ? "xmark.circle.fill" : "circle"))
                }
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(fill, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: よく走った日

    private var newRanking: some View {
        let days = recap.dailyDistances
        let top = Array(days.prefix(10))
        let maxDistance = top.first?.distance ?? 1
        return TwoBeatSlide(title: "一番走った日は？", titleColor: RecapPalette.navy, style: .wipe, animated: animated) { _ in
            page("よく走った日", headerColor: RecapPalette.navy, background: RecapPalette.lime) { ink in
                VStack(alignment: .leading, spacing: 8) {
                    if let first = top.first {
                        Text(Self.dayText(first.day))
                            .font(.system(size: 34, weight: .heavy))
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            RollingNumberText(text: String(format: "%.2f", first.distance / 1000), size: 64, animated: animated)
                            Text("km").font(.system(size: 24, weight: .heavy))
                        }
                        .padding(.bottom, 10)
                    }
                    ForEach(Array(top.enumerated()), id: \.offset) { rank, day in
                        HStack(spacing: 8) {
                            Text("\(rank + 1)")
                                .font(.system(size: 12, weight: .heavy).monospacedDigit())
                                .frame(width: 18)
                            Text(Self.dayText(day.day))
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 88, alignment: .leading)
                            GrowingBar(
                                fraction: day.distance / maxDistance,
                                color: rank == 0 ? RecapPalette.navy : ink.opacity(0.45),
                                animated: animated, delay: 0.5 + Double(rank) * 0.07
                            )
                            .frame(height: 8)
                            Text(String(format: "%.2f", day.distance / 1000))
                                .font(.system(size: 12, weight: .bold).monospacedDigit())
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(height: 18)
                    }
                }
            }
        }
    }

    // MARK: 活動カレンダーと継続（§27.7 E）

    private var newCalendar: some View {
        let cal = Calendar.current
        let start = recap.month.start()
        let daysInMonth = cal.range(of: .day, in: .month, for: start)?.count ?? 30
        // 月曜始まり: 1日の曜日（日曜=1）から、前に空ける数を求める
        let leading = (cal.component(.weekday, from: start) + 5) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return TwoBeatSlide(title: "何日、\nピッチに立った？", titleColor: RecapPalette.orange, style: .tiles, animated: animated) { _ in
            page("プレーした日", headerColor: RecapPalette.orange, background: RecapPalette.lilac) { ink in
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        RollingNumberText(text: "\(recap.playedDays.count)", size: 96, animated: animated)
                        Text("日").font(.system(size: 30, weight: .heavy))
                    }
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { label in
                            Text(label).font(.system(size: 11, weight: .bold)).opacity(0.6)
                        }
                        ForEach(0..<(leading + daysInMonth), id: \.self) { cell in
                            let day = cell - leading + 1
                            if day < 1 {
                                Color.clear.frame(height: 30)
                            } else if recap.playedDays.contains(day) {
                                Text("\(day)")
                                    .font(.system(size: 13, weight: .heavy).monospacedDigit())
                                    .foregroundStyle(RecapPalette.ink(on: RecapPalette.orange))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(Circle().fill(RecapPalette.orange))
                                    .reveal(animated, delay: 0.6 + Double(day) * 0.04, .pop)
                            } else {
                                Text("\(day)")
                                    .font(.system(size: 13).monospacedDigit())
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .background(Circle().fill(ink.opacity(0.06)))
                                    .opacity(0.55)
                            }
                        }
                    }
                    if recap.weeklyStreak >= 2 {
                        Label("\(recap.weeklyStreak)週連続でプレー", systemImage: "flame.fill")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(RecapPalette.orange)
                            .reveal(animated, delay: 2.0, .pop)
                    }
                }
            }
        }
    }

    // MARK: 最速のスプリント（§27.7 A）

    @ViewBuilder
    private var newSprint: some View {
        if let replay = sprintReplay {
            TwoBeatSlide(title: "一番速かった\n瞬間は…", titleColor: RecapPalette.orange, style: .dash, animated: animated) { _ in
                page("最速のスプリント", headerColor: RecapPalette.orange, background: RecapPalette.navy) { _ in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(Self.dayText(replay.date))
                            .font(.system(size: 22, weight: .heavy))
                        SprintReplayView(replay: replay, width: 196, startDate: startDate.addingTimeInterval(1.0), animated: animated)
                            .frame(maxWidth: .infinity)
                        Text(String(format: "距離 %.0f m ・ %.1f 秒", replay.distance, replay.duration))
                            .font(.system(size: 14, weight: .semibold))
                            .opacity(0.8)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    // MARK: 一番よかったセッション

    private var newBest: some View {
        let session = recap.bestSession
        return TwoBeatSlide(title: "ベストゲームは…", titleColor: RecapPalette.lilac, style: .spotlight, animated: animated) { _ in
            page("一番よかったセッション", headerColor: RecapPalette.lilac, background: RecapPalette.orange) { _ in
                VStack(alignment: .leading, spacing: 14) {
                    Text(Self.dayText(session.date))
                        .font(.system(size: 40, weight: .heavy))
                    HStack(alignment: .top, spacing: 16) {
                        if let bestGrid {
                            RecapHeatmapView(grid: bestGrid, width: 140)
                                .reveal(animated, delay: 0.3, .pop)
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            stat("走行距離", String(format: "%.2f km", session.totalDistance / 1000))
                            stat(session.isLowGPSAccuracy ? "最高速度（参考値）" : "最高速度", String(format: "%.1f km/h", session.maxSpeed * 3.6))
                            stat("スプリント", "\(session.sprintCount ?? 0) 回")
                            stat("総合スコア", "\(recap.bestSessionScore) 点")
                        }
                        .reveal(animated, delay: 0.5)
                    }
                }
            }
        }
    }

    // MARK: 先月と比べて（§27.7 F）

    private var newComparison: some View {
        TwoBeatSlide(title: "先月の自分と\n比べると…", titleColor: RecapPalette.navy, style: .split, animated: animated) { _ in
            page("先月と比べて", headerColor: RecapPalette.navy, background: RecapPalette.cream) { ink in
                VStack(alignment: .leading, spacing: 16) {
                    if recap.hasComparison {
                        if let change = recap.distancePerMinute {
                            comparisonRow("1分あたりの走行距離", change: change, ink: ink, delay: 0.3) { String(format: "%.0f m", $0) }
                        }
                        if let change = recap.maxSpeed {
                            comparisonRow("最高速度", change: change, ink: ink, delay: 0.6) { String(format: "%.1f km/h", $0 * 3.6) }
                        }
                        if let change = recap.sprintsPerSession {
                            comparisonRow("1回あたりのスプリント", change: change, ink: ink, delay: 0.9) { String(format: "%.1f 回", $0) }
                        }
                        Text("±5%以内は「維持」としています")
                            .font(.system(size: 11))
                            .opacity(0.55)
                    } else {
                        Text("先月の記録がないため\n比べられません。\n来月は、今月と比べられます。")
                            .font(.system(size: 22, weight: .heavy))
                    }
                    if !recap.personalBests.isEmpty {
                        personalBestBox
                            .reveal(animated, delay: 1.3, .pop)
                    }
                }
            }
        }
    }

    /// 先月（灰色）と今月（オレンジ）の棒を並べて伸ばす
    private func comparisonRow(_ title: String, change: RecapMetricChange, ink: Color, delay: Double, format: @escaping (Double) -> String) -> some View {
        let maxValue = max(change.previous, change.current, 0.0001)
        let (symbol, text, color): (String, String, Color) = {
            switch change.direction {
            case .up:   return ("arrow.up.right", "伸びた", RecapPalette.pitch)
            case .kept: return ("arrow.right", "維持", RecapPalette.navy)
            case .down: return ("arrow.down.right", "下がった", RecapPalette.orange)
            }
        }()
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 13, weight: .bold))
                Spacer()
                Label(text, systemImage: symbol)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(color)
                    .reveal(animated, delay: delay + 0.6, .pop)
            }
            barLine("先月", value: change.previous, fraction: change.previous / maxValue, color: ink.opacity(0.3), delay: delay, format: format)
            barLine("今月", value: change.current, fraction: change.current / maxValue, color: RecapPalette.orange, delay: delay + 0.15, format: format)
        }
    }

    private func barLine(_ label: String, value: Double, fraction: Double, color: Color, delay: Double, format: (Double) -> String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, alignment: .leading)
            GrowingBar(fraction: fraction, color: color, animated: animated, delay: delay)
                .frame(height: 14)
            Text(format(value))
                .font(.system(size: 13, weight: .heavy).monospacedDigit())
                .frame(width: 76, alignment: .trailing)
        }
    }

    private var personalBestBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("自己ベスト更新！", systemImage: "trophy.fill")
                .font(.system(size: 18, weight: .heavy))
            ForEach(recap.personalBests, id: \.title) { best in
                HStack {
                    Text(best.title).font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text("\(best.previous) → ").font(.system(size: 12).monospacedDigit()).opacity(0.7)
                    Text(best.value).font(.system(size: 15, weight: .heavy).monospacedDigit())
                }
            }
        }
        .foregroundStyle(RecapPalette.ink(on: RecapPalette.lime))
        .padding(14)
        .background(RecapPalette.lime, in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: 二つ名と積み上がるヒートマップ

    private var newStyle: some View {
        TwoBeatSlide(title: "\(recap.month.title)のあなたは…", titleColor: RecapPalette.lime, style: .zoom, animated: animated) { _ in
            page("\(recap.month.title)の二つ名", headerColor: RecapPalette.lime, background: RecapPalette.pitch) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    Text(nickname)
                        .font(.system(size: 40, weight: .heavy))
                        .lineLimit(1)  // 言葉の途中で改行しないよう、1行に収まるまで小さくする
                        .minimumScaleFactor(0.45)
                        .reveal(animated, delay: 0.2, .pop)
                    Capsule()
                        .fill(RecapPalette.lime)
                        .frame(height: 5)
                        .reveal(animated, delay: 0.5)
                    HStack(spacing: 8) {
                        chip("タイプ: \(recap.topPlayerType.rawValue)")
                        if let position = recap.topPosition {
                            chip("ポジション: \(position.displayName)")
                        }
                    }
                    if let frames = heatmapFrames, !frames.isEmpty {
                        AccumulatingHeatmapView(
                            frames: frames, month: recap.month, width: 170,
                            startDate: startDate.addingTimeInterval(1.0), animated: animated
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    // MARK: 獲得したバッジ

    private var newBadges: some View {
        TwoBeatSlide(title: "手に入れた\nバッジ", titleColor: RecapPalette.orange, style: .drop, animated: animated) { _ in
            page("\(recap.month.title)に獲得したバッジ", headerColor: RecapPalette.orange, background: RecapPalette.lime) { ink in
                VStack(alignment: .leading, spacing: 10) {
                    RollingNumberText(text: "\(recap.newBadges.count)", size: 72, animated: animated)
                    ForEach(Array(recap.newBadges.prefix(5).enumerated()), id: \.offset) { offset, badge in
                        HStack(spacing: 14) {
                            Image(systemName: badge.sfSymbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(RecapPalette.ink(on: RecapPalette.orange))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(RecapPalette.orange))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(badge.name).font(.system(size: 17, weight: .heavy))
                                if let tier = badge.tier {
                                    Text(tier.displayName).font(.system(size: 13, weight: .semibold)).opacity(0.7)
                                }
                            }
                        }
                        .reveal(animated, delay: 0.6 + Double(offset) * 0.18, .pop)
                    }
                    if recap.newBadges.count > 5 {
                        Text("ほか \(recap.newBadges.count - 5) 個").font(.system(size: 14, weight: .bold)).opacity(0.7)
                    }
                }
            }
        }
    }

    // MARK: まとめ（Stravaの「TOTALS」のように色の違うタイルを並べる）

    private var newSummary: some View {
        page("\(recap.month.title)のまとめ", headerColor: RecapPalette.pitch, background: RecapPalette.cream) { _ in
            VStack(alignment: .leading, spacing: 10) {
                Text(nickname)
                    .font(.system(size: 26, weight: .heavy))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                let tiles: [(String, String, Color)] = {
                    var list: [(String, String, Color)] = [
                        ("回数", "\(recap.sessionCount) 回", RecapPalette.orange),
                        ("プレー時間", Self.durationText(recap.totalDuration), RecapPalette.navy),
                        ("走行距離", String(format: "%.1f km", recap.totalDistance / 1000), RecapPalette.lime),
                        ("スプリント", "\(recap.totalSprints) 回", RecapPalette.lilac),
                    ]
                    if let speed = recap.bestMaxSpeed {
                        list.append(("最高速度", String(format: "%.1f km/h", speed * 3.6), RecapPalette.pitch))
                    }
                    list.append(("プレーした日", "\(recap.playedDays.count) 日", RecapPalette.orange))
                    return list
                }()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { i, tile in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tile.0).font(.system(size: 11, weight: .bold)).opacity(0.75)
                            Text(tile.1)
                                .font(.system(size: 20, weight: .heavy).monospacedDigit())
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .foregroundStyle(RecapPalette.ink(on: tile.2))
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .padding(.horizontal, 12)
                        .background(tile.2, in: RoundedRectangle(cornerRadius: 10))
                        .reveal(animated, delay: 0.2 + Double(i) * 0.1, .pop)
                    }
                }
                Text("\(recap.month.title)もおつかれさま。\n来月もピッチで。")
                    .font(.system(size: 22, weight: .heavy))
                    .padding(.top, 6)
                    .reveal(animated, delay: 1.0)
            }
        }
    }

    // MARK: 部品

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12, weight: .bold)).opacity(0.7)
            Text(value).font(.system(size: 22, weight: .heavy).monospacedDigit())
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2), in: Capsule())
    }

    static func durationText(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60)時間\(minutes % 60)分" : "\(minutes)分"
    }

    static func shortDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
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

    /// 再生にかける秒数。実際の時間（数秒）に近く、短すぎないようにする（画面の秒数の計算にも使う）
    static func playDuration(for replay: SprintReplay) -> Double { min(5, max(3, replay.duration + 1.5)) }
    private var playDuration: Double { Self.playDuration(for: replay) }
    /// 再生を始めるまでの間
    static let delay: Double = 0.6
    private var delay: Double { Self.delay }

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

    /// 1コマを見せる秒数。日数が多くても4秒ほどで積み上がるようにする（画面の秒数の計算にも使う）
    static func step(frameCount: Int) -> Double { min(0.7, 4.0 / Double(max(frameCount, 1))) }
    private var step: Double { Self.step(frameCount: frames.count) }
    static let delay: Double = 0.8
    private var delay: Double { Self.delay }

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
