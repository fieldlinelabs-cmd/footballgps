//
//  FieldPositioningView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import CoreLocation

/// フィールド上でのポジショニング（移動軌跡）を表示するビュー
struct FieldPositioningView: View {
    let gpsData: GPSData
    let field: Field
    let orientation: CourtOrientation
    let currentPointIndex: Int
    var sprintSegments: [SprintSegment] = []

    var body: some View {
        GeometryReader { geometry in
            let (drawWidth, drawHeight) = fieldDrawSize(in: geometry.size)
            let allPoints = convertedPoints(in: geometry.size)
            ZStack {
                // フィールド背景
                FieldBackgroundView()
                    .frame(width: drawWidth + 40, height: drawHeight + 40)

                // GPS軌跡: 再生位置を00:00から動かしていれば、その位置までを実線・以降を点線にする
                // （動かしていなければ全体を実線）
                if !allPoints.isEmpty {
                    let keptIndex = min(currentPointIndex, allPoints.count - 1)
                    let boundaryIndex: Int? = keptIndex > 0 ? keptIndex : nil
                    let switchIndex = courtSwitchIndex

                    if let boundaryIndex, allPoints.indices.contains(boundaryIndex) {
                        if let keptPath = createPath(points: Array(allPoints[0...boundaryIndex]), breakIndex: switchIndex) {
                            keptPath.stroke(Color.blue, lineWidth: 2)
                        }
                        if boundaryIndex < allPoints.count - 1,
                           let tailPath = createPath(
                               points: Array(allPoints[boundaryIndex...]),
                               breakIndex: switchIndex.map { $0 - boundaryIndex }
                           ) {
                            tailPath.stroke(Color.gray.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                        }
                    } else if let fullPath = createPath(points: allPoints, breakIndex: switchIndex) {
                        fullPath.stroke(Color.blue, lineWidth: 2)
                    }
                }

                // スプリント区間（赤線）
                ForEach(sprintSegments.indices, id: \.self) { i in
                    let seg = sprintSegments[i]
                    if let path = createPath(points: sprintPoints(seg, in: geometry.size)) {
                        path
                            .stroke(Color.red, lineWidth: 2)
                    }
                }

                // スタート地点
                if let firstPoint = allPoints.first {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .position(firstPoint)

                    Text("START")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.green)
                        .position(x: firstPoint.x, y: firstPoint.y - 15)
                }

                // ゴール地点
                if let lastPoint = allPoints.last {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 12, height: 12)
                        .position(lastPoint)

                    Text("END")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.red)
                        .position(x: lastPoint.x, y: lastPoint.y - 15)
                }

                // 選手ドット（再生位置）
                if !allPoints.isEmpty {
                    let dotCenter = allPoints[min(currentPointIndex, allPoints.count - 1)]
                    Circle()
                        .fill(Color.white)
                        .frame(width: 18, height: 18)
                        .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 1)
                        .position(dotCenter)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 12, height: 12)
                        .position(dotCenter)
                }
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .padding()
    }
    
    /// GPS座標をビューの座標系に変換
    private func convertedPoints(in size: CGSize) -> [CGPoint] {
        let padding: CGFloat = 20
        let availableWidth = size.width - padding * 2
        let availableHeight = size.height - padding * 2

        // フィールドのアスペクト比（長辺が縦になるよう自動計算）
        let fieldRatio = autoFieldRatio(field.dimensions)

        // 描画領域のサイズを計算
        var drawWidth = availableWidth
        var drawHeight = availableWidth / fieldRatio

        if drawHeight > availableHeight {
            drawHeight = availableHeight
            drawWidth = drawHeight * fieldRatio
        }

        let offsetX = (size.width - drawWidth) / 2
        let offsetY = (size.height - drawHeight) / 2

        return gpsData.points.compactMap { point in
            guard let coord = field.orientedCoordinate(of: point, orientation: orientation) else {
                return nil
            }

            let x = offsetX + (coord.x / field.dimensions.width)  * drawWidth
            let y = offsetY + (1.0 - coord.y / field.dimensions.length) * drawHeight

            return CGPoint(x: x, y: y)
        }
    }

    /// 変換後の軌跡で、後半の入れ替えの最初の点の位置（ここで線をつながない）
    private var courtSwitchIndex: Int? {
        guard let switchDate = orientation.switchDate else { return nil }
        return gpsData.points.prefix { $0.timestamp < switchDate }
            .filter { field.orientedCoordinate(of: $0, orientation: orientation) != nil }
            .count
    }
    
    /// 描画枠の縦横比（横＝ゴールライン、縦＝タッチライン。登録画面で設定した4隅の位置関係のまま描く）
    /// fieldRatio < 1 → drawHeight > drawWidth（縦長）
    private func autoFieldRatio(_ dimensions: Field.FieldDimensions) -> CGFloat {
        dimensions.width / dimensions.length
    }

    /// 描画領域のサイズを計算（FieldBackgroundView のフレーム合わせに使用）
    private func fieldDrawSize(in size: CGSize) -> (CGFloat, CGFloat) {
        let padding: CGFloat = 20
        let availableWidth  = size.width  - padding * 2
        let availableHeight = size.height - padding * 2
        let fieldRatio = autoFieldRatio(field.dimensions)
        var drawWidth  = availableWidth
        var drawHeight = availableWidth / fieldRatio
        if drawHeight > availableHeight {
            drawHeight = availableHeight
            drawWidth  = drawHeight * fieldRatio
        }
        return (drawWidth, drawHeight)
    }

    /// スプリント区間のGPS点をビュー座標に変換
    private func sprintPoints(_ segment: SprintSegment, in size: CGSize) -> [CGPoint] {
        let padding: CGFloat = 20
        let availableWidth  = size.width  - padding * 2
        let availableHeight = size.height - padding * 2
        let fieldRatio = autoFieldRatio(field.dimensions)
        var drawWidth  = availableWidth
        var drawHeight = availableWidth / fieldRatio
        if drawHeight > availableHeight {
            drawHeight = availableHeight
            drawWidth  = drawHeight * fieldRatio
        }
        let offsetX = (size.width  - drawWidth)  / 2
        let offsetY = (size.height - drawHeight) / 2

        let end = min(segment.endIndex, gpsData.points.count - 1)
        guard segment.startIndex <= end else { return [] }

        return gpsData.points[segment.startIndex...end].compactMap { point in
            guard let coord = field.orientedCoordinate(of: point, orientation: orientation) else { return nil }
            return CGPoint(
                x: offsetX + (coord.x / field.dimensions.width)  * drawWidth,
                y: offsetY + (1.0 - coord.y / field.dimensions.length) * drawHeight
            )
        }
    }

    /// breakIndex の点の手前では線をつながない
    private func createPath(points: [CGPoint], breakIndex: Int? = nil) -> Path? {
        guard !points.isEmpty else { return nil }
        var path = Path()
        path.move(to: points[0])
        for (index, point) in points.enumerated().dropFirst() {
            if index == breakIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}

/// サッカーフィールドの背景を描画
struct FieldBackgroundView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // フィールドの緑色
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.3))
                
                // フィールドのライン
                FieldLinesView()
                    .stroke(Color.white.opacity(0.6), lineWidth: 2)
            }
        }
    }
}

/// フィールドのラインを描画（90度回転: ゴールが上下）
struct FieldLinesView: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let padding: CGFloat = 20
        let fieldRect = rect.insetBy(dx: padding, dy: padding)
        
        // 外枠
        path.addRect(fieldRect)
        
        // センターライン（横向き: 上下を分ける）
        path.move(to: CGPoint(x: fieldRect.minX, y: fieldRect.midY))
        path.addLine(to: CGPoint(x: fieldRect.maxX, y: fieldRect.midY))
        
        // センターサークル
        let centerCircleRadius: CGFloat = 30
        path.addEllipse(in: CGRect(
            x: fieldRect.midX - centerCircleRadius,
            y: fieldRect.midY - centerCircleRadius,
            width: centerCircleRadius * 2,
            height: centerCircleRadius * 2
        ))
        
        // ペナルティエリア（上）
        let penaltyWidth = fieldRect.width * 0.4
        let penaltyHeight = fieldRect.height * 0.15
        path.addRect(CGRect(
            x: fieldRect.midX - penaltyWidth / 2,
            y: fieldRect.minY,
            width: penaltyWidth,
            height: penaltyHeight
        ))
        
        // ペナルティエリア（下）
        path.addRect(CGRect(
            x: fieldRect.midX - penaltyWidth / 2,
            y: fieldRect.maxY - penaltyHeight,
            width: penaltyWidth,
            height: penaltyHeight
        ))
        
        // ゴールエリア（上）
        let goalWidth = fieldRect.width * 0.2
        let goalHeight = fieldRect.height * 0.05
        path.addRect(CGRect(
            x: fieldRect.midX - goalWidth / 2,
            y: fieldRect.minY,
            width: goalWidth,
            height: goalHeight
        ))
        
        // ゴールエリア（下）
        path.addRect(CGRect(
            x: fieldRect.midX - goalWidth / 2,
            y: fieldRect.maxY - goalHeight,
            width: goalWidth,
            height: goalHeight
        ))
        
        return path
    }
}

#Preview {
    FieldPositioningView(
        gpsData: MockData.generateMockGPSData(sessionId: "preview"),
        field: MockData.mockField,
        orientation: CourtOrientation(isFlipped: false),
        currentPointIndex: 0
    )
    .frame(height: 400)
}
