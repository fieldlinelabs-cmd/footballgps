//
//  ViewsMeasurementHelpView.swift
//  FootballGPS
//
//  ヘルプ「数値の見方と、プレー中の着け方」（統計推移仕様書 §10.2）
//

import SwiftUI

struct MeasurementHelpView: View {
    var body: some View {
        List {
            Section {
                Label {
                    Text("プレー中は、周りの選手の安全のため、リストバンドやサポーターでApple Watchを覆ってください。")
                } icon: {
                    Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
                }
                Text("公式戦では、腕時計は装身具として外すのが一般的です。練習や練習試合、個人のトレーニングなどでお使いください。着用できるかは、チームや大会の決まりに従ってください。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("プレー中の着け方")
            }

            Section {
                Text("雨や汗でリストバンドが濡れると、GPSの精度が下がることがあります。精度が下がった記録はアプリが自動で判定し、セッションの画面に「GPSの精度が低い記録」と表示します。その記録の最高速度は参考値として扱い、自己ベストや平均には使いません。スプリントの回数も誤差が出やすくなります。")
            } header: {
                Text("GPSの精度について")
            }

            Section {
                helpRow(title: "目安として信頼しやすい数値", icon: "checkmark.circle.fill", color: .green,
                        text: "走行距離、ヒートマップ、守備・中盤・攻撃の割合、時間帯別の運動量。長い時間の動きをまとめた値なので、誤差が平均されやすくなります。")
                helpRow(title: "誤差が出やすい数値", icon: "exclamationmark.triangle.fill", color: .orange,
                        text: "最高速度、スプリントの回数。Apple Watchは約1秒ごとに位置を測るため、短いダッシュは実際より低めに出たり、取りこぼしたりすることがあります。")
                helpRow(title: "おすすめの使い方", icon: "chart.line.uptrend.xyaxis", color: .blue,
                        text: "他の人と比べるより、同じような条件での自分の変化を見るのに向いています。")
            } header: {
                Text("数値の見方")
            }

            Section {
                Text("記録を始めたら、Apple Watchが振動して位置が決まるのを待ってから動いてください。")
                Text("屋根の下や、高い建物の近くでは精度が下がりやすくなります。")
            } header: {
                Text("精度を上げるコツ")
            }
        }
        .navigationTitle("数値の見方と着け方")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func helpRow(title: String, icon: String, color: Color, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
        }
        .padding(.vertical, 2)
    }
}
