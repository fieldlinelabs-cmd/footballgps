//
//  ViewsSplashView.swift
//  FootballGPS
//
//  起動時に一瞬だけ表示するオープニング画面（§AppIconのデザインに合わせたブランディング）
//

import SwiftUI

struct SplashView: View {
    @State private var iconScale: CGFloat = 0.6
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0

    private let deepBlue = Color(red: 0.02, green: 0.13, blue: 0.36)
    private let fieldBlue = Color(red: 0.06, green: 0.29, blue: 0.63)
    private let accentCyan = Color(red: 0.18, green: 0.9, blue: 0.83)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [deepBlue, fieldBlue],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(accentCyan.opacity(0.35))
                        .frame(width: 150, height: 150)
                        .blur(radius: 28)

                    Image("AppLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 108, height: 108)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                Text("FootballGPS")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(textOpacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.35).delay(0.2)) {
                textOpacity = 1.0
            }
        }
    }
}

#Preview {
    SplashView()
}
