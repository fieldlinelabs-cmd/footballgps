//
//  ViewsImageCropView.swift
//  FootballGPS
//
//  写真登録（プロフィール写真・チームエンブレム）共通のトリミング画面。
//  ドラッグで位置調整・ピンチで拡大縮小した円形範囲を、正方形画像として書き出す。
//

import SwiftUI

struct ImageCropView: View {
    let image: UIImage
    var onCancel: () -> Void
    var onComplete: (UIImage) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    @Environment(\.displayScale) private var displayScale

    private let baseSize: CGFloat = 300
    private let cropSize: CGFloat = 240
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 8.0

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Spacer()

                    ZStack {
                        transformedImage
                            .frame(width: baseSize, height: baseSize)
                            .clipped()

                        holeMask

                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                            .frame(width: cropSize, height: cropSize)
                    }
                    .frame(width: baseSize, height: baseSize)
                    .contentShape(Rectangle())
                    .gesture(dragGesture)
                    .simultaneousGesture(magnifyGesture)

                    Text("ドラッグで位置調整、ピンチで拡大・縮小できます")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()
                }
            }
            .navigationTitle("位置調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") { complete() }
                }
            }
        }
    }

    private var transformedImage: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: baseSize, height: baseSize)
            .scaleEffect(scale)
            .offset(offset)
    }

    @ViewBuilder
    private var holeMask: some View {
        Rectangle()
            .fill(Color.black.opacity(0.6))
            .frame(width: baseSize, height: baseSize)
            .mask(
                Rectangle()
                    .overlay(
                        Circle()
                            .frame(width: cropSize, height: cropSize)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()
            )
            .allowsHitTesting(false)
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                offset = clampedOffset(CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                ))
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnifyGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(maxScale, max(minScale, lastScale * value))
                offset = clampedOffset(offset)
            }
            .onEnded { _ in
                lastScale = scale
                lastOffset = offset
            }
    }

    /// 画像の縁が円形クロップ範囲より内側に入り込まないよう、オフセットの可動域を制限する
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let maxOffset = max(0, (baseSize * scale - cropSize) / 2)
        return CGSize(
            width: min(maxOffset, max(-maxOffset, proposed.width)),
            height: min(maxOffset, max(-maxOffset, proposed.height))
        )
    }

    private func complete() {
        let renderer = ImageRenderer(content: croppedContent)
        renderer.scale = displayScale
        onComplete(renderer.uiImage ?? image)
    }

    private var croppedContent: some View {
        transformedImage
            .frame(width: cropSize, height: cropSize)
            .clipped()
    }
}
