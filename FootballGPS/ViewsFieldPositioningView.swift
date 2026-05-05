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
    let isFlipped: Bool
    
    var body: some View {
        GeometryReader { geometry in
            let (drawWidth, drawHeight) = fieldDrawSize(in: geometry.size)
            ZStack {
                // フィールド背景
                FieldBackgroundView()
                    .frame(width: drawWidth + 40, height: drawHeight + 40)

                // GPS軌跡
                if let path = createPath(in: geometry.size) {
                    path
                        .stroke(Color.blue, lineWidth: 2)
                }
                
                // スタート地点
                if let firstPoint = convertedPoints(in: geometry.size).first {
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
                if let lastPoint = convertedPoints(in: geometry.size).last {
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
            guard let fieldCoord = field.convertToFieldCoordinate(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else {
                return nil
            }

            // isFlipped の場合はフィールド中心を軸に180度回転 (x, y) → (width-x, length-y)
            let fx = isFlipped ? field.dimensions.width  - fieldCoord.x : fieldCoord.x
            let fy = isFlipped ? field.dimensions.length - fieldCoord.y : fieldCoord.y

            // 90度回転のため、x と y を入れ替える（ヒートマップと同じ仕様）
            let x = offsetX + (fy / field.dimensions.length) * drawWidth
            let y = offsetY + (fx / field.dimensions.width) * drawHeight

            return CGPoint(x: x, y: y)
        }
    }
    
    /// 長辺が縦に表示されるよう fieldRatio を自動計算
    /// fieldRatio < 1 → drawHeight > drawWidth（縦長）
    private func autoFieldRatio(_ dimensions: Field.FieldDimensions) -> CGFloat {
        let longer  = max(dimensions.length, dimensions.width)
        let shorter = min(dimensions.length, dimensions.width)
        return shorter / longer
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

    /// パスを作成
    private func createPath(in size: CGSize) -> Path? {
        let points = convertedPoints(in: size)
        guard !points.isEmpty else { return nil }
        
        var path = Path()
        path.move(to: points[0])
        
        for point in points.dropFirst() {
            path.addLine(to: point)
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
        isFlipped: false
    )
    .frame(height: 400)
}
