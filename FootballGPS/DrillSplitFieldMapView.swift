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
    let isFlipped: Bool
    let ranges: [(start: TimeInterval, end: TimeInterval)]
    let breaks: [DrillBreakInterval]

    /// ドリル区間ごとに巡回して使う色（DrillSplitReviewViewの一覧行のインジケーターとも共有する）
    static let segmentColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo]

    var body: some View {
        GeometryReader { geometry in
            let (drawWidth, drawHeight) = fieldDrawSize(in: geometry.size)
            ZStack {
                FieldBackgroundView()
                    .frame(width: drawWidth + 40, height: drawHeight + 40)

                // 除外区間（フィールド入場前/退場後の移動、ドリル間の休憩）: グレーの破線
                ForEach(Array(breaks.enumerated()), id: \.offset) { _, brk in
                    let points = convertedPoints(
                        for: SessionDataManager.slicedPoints(gpsData.points, from: brk.startOffset, to: brk.endOffset),
                        in: geometry.size
                    )
                    if let path = createPath(points: points) {
                        path.stroke(Color.gray.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    }
                }

                // 採用されるドリル区間: 区間ごとに色分けした実線
                ForEach(Array(ranges.enumerated()), id: \.offset) { index, range in
                    let points = convertedPoints(
                        for: SessionDataManager.slicedPoints(gpsData.points, from: range.start, to: range.end),
                        in: geometry.size
                    )
                    if let path = createPath(points: points) {
                        path.stroke(Self.segmentColors[index % Self.segmentColors.count], lineWidth: 3)
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
            guard let fieldCoord = field.convertToFieldCoordinate(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else { return nil }

            // isFlipped の場合はフィールド中心を軸に180度回転
            let fx = isFlipped ? field.dimensions.width - fieldCoord.x : fieldCoord.x
            let fy = isFlipped ? field.dimensions.length - fieldCoord.y : fieldCoord.y

            let x = offsetX + (fx / field.dimensions.width) * drawWidth
            let y = offsetY + (1.0 - fy / field.dimensions.length) * drawHeight
            return CGPoint(x: x, y: y)
        }
    }

    /// 長辺が縦に表示されるよう fieldRatio を自動計算
    private func autoFieldRatio(_ dimensions: Field.FieldDimensions) -> CGFloat {
        let longer = max(dimensions.length, dimensions.width)
        let shorter = min(dimensions.length, dimensions.width)
        return shorter / longer
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

    private func createPath(points: [CGPoint]) -> Path? {
        guard !points.isEmpty else { return nil }
        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() {
            path.addLine(to: point)
        }
        return path
    }
}
