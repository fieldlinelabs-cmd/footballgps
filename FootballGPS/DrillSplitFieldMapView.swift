//
//  DrillSplitFieldMapView.swift
//  FootballGPS
//
//  ドリル分割確認画面（DrillSplitReviewView）用のミニマップ。
//  フィールド境界とGPS軌跡を、採用されるドリル区間ごとに色分けし、
//  除外される区間（移動・休憩）はグレーの破線で表示する。
//

import SwiftUI
import CoreLocation

struct DrillSplitFieldMapView: View {
    let gpsData: GPSData
    let field: Field
    let orientation: CourtOrientation
    let ranges: [(start: TimeInterval, end: TimeInterval)]
    let breaks: [DrillBreakInterval]
    /// 再生位置（先頭点からの経過秒）。手動切り出し画面でのみ渡し、地図上にマーカーを出す
    var currentOffset: TimeInterval? = nil

    /// ドリル区間ごとに巡回して使う色（DrillSplitReviewView・DrillSplitManualEditViewの一覧行とも共有する）
    static let segmentColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]

    var body: some View {
        GeometryReader { geometry in
            let (drawWidth, drawHeight) = fieldDrawSize(in: geometry.size)
            ZStack {
                FieldBackgroundView()
                    .frame(width: drawWidth + 40, height: drawHeight + 40)

                // 除外区間（フィールド入場前/退場後の移動、ドリル間の休憩）: グレーの破線
                ForEach(Array(breaks.enumerated()), id: \.offset) { _, brk in
                    if let path = createPath(
                        for: SessionDataManager.slicedPoints(gpsData.points, from: brk.startOffset, to: brk.endOffset),
                        in: geometry.size
                    ) {
                        path.stroke(Color.gray.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                }

                // 採用されるドリル区間: 区間ごとに色分けした実線
                ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                    if let path = createPath(
                        for: SessionDataManager.slicedPoints(gpsData.points, from: range.start, to: range.end),
                        in: geometry.size
                    ) {
                        path.stroke(Self.segmentColors[index % Self.segmentColors.count], lineWidth: 3)
                    }
                }

                // 再生位置マーカー
                if let currentOffset, !gpsData.points.isEmpty {
                    let index = SessionDataManager.gpsIndex(in: gpsData.points, atElapsed: currentOffset)
                    if let position = convertedPoints(for: [gpsData.points[index]], in: geometry.size).first {
                        Circle()
                            .fill(Color.red)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .frame(width: 14, height: 14)
                            .position(position)
                    }
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
    }

    /// GPS座標をビューの座標系に変換（FieldPositioningView.convertedPoints と同じ計算式）
    private func convertedPoints(for points: [GPSPoint], in size: CGSize) -> [CGPoint] {
        let padding: CGFloat = 20
        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2
        let fieldRatio = autoFieldRatio(field.dimensions)

        var drawWidth = availableWidth
        var drawHeight = availableWidth / fieldRatio
        if drawHeight > availableHeight {
            drawHeight = availableHeight
            drawWidth = drawHeight * fieldRatio
        }

        let offsetX = (size.width - drawWidth) / 2
        let offsetY = (size.height - drawHeight) / 2

        return points.compactMap { point in
            guard let coord = field.orientedCoordinate(of: point, orientation: orientation) else { return nil }

            let x = offsetX + (coord.x / field.dimensions.width) * drawWidth
            let y = offsetY + (1.0 - coord.y / field.dimensions.length) * drawHeight
            return CGPoint(x: x, y: y)
        }
    }

    /// 描画枠の縦横比（横＝ゴールライン、縦＝タッチライン。登録画面で設定した4隅の位置関係のまま描く）
    private func autoFieldRatio(_ dimensions: Field.FieldDimensions) -> CGFloat {
        dimensions.width / dimensions.length
    }

    private func fieldDrawSize(in size: CGSize) -> (CGFloat, CGFloat) {
        let padding: CGFloat = 20
        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2
        let fieldRatio = autoFieldRatio(field.dimensions)
        var drawWidth = availableWidth
        var drawHeight = availableWidth / fieldRatio
        if drawHeight > availableHeight {
            drawHeight = availableHeight
            drawWidth = drawHeight * fieldRatio
        }
        return (drawWidth, drawHeight)
    }

    /// 後半の入れ替えをまたいで線をつながない
    private func createPath(for points: [GPSPoint], in size: CGSize) -> Path? {
        var path = Path()
        for part in orientation.splitAtSwitch(points) {
            let converted = convertedPoints(for: part, in: size)
            guard let first = converted.first else { continue }
            path.move(to: first)
            for point in converted.dropFirst() {
                path.addLine(to: point)
            }
        }
        return path.isEmpty ? nil : path
    }
}
