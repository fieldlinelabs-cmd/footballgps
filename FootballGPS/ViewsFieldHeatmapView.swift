//
//  FieldHeatmapView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI
import CoreLocation

/// フィールド上での活動ヒートマップを表示するビュー
struct FieldHeatmapView: View {
    let gpsData: GPSData
    let field: Field
    let isFlipped: Bool
    
    // ヒートマップのグリッドサイズ（倍密化: 約2.5m/セル）
    private let gridRows = 28 // 幅方向（width: 68m）
    private let gridCols = 40 // 長さ方向（length: 105m）
    
    var body: some View {
        GeometryReader { geometry in
            let (drawWidth, drawHeight) = fieldDrawSize(in: geometry.size)
            let thirdRatios = SessionDataManager.computeThirdRatios(
                gpsData: gpsData, field: field, isFlipped: isFlipped
            )
            ZStack {
                // フィールド背景
                FieldBackgroundView()
                    .frame(width: drawWidth + 40, height: drawHeight + 40)

                // ヒートマップグリッド
                HeatmapGridView(
                    heatmap: calculateHeatmap(),
                    rows: gridRows,
                    cols: gridCols,
                    size: geometry.size,
                    field: field
                )
                .blur(radius: 6)

                // サード境界線・ラベルオーバーレイ
                ThirdLinesOverlay(
                    thirdRatios: thirdRatios,
                    field: field,
                    size: geometry.size
                )
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .shadow(radius: 2)
        }
        .padding()
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

    /// ヒートマップデータを計算
    private func calculateHeatmap() -> [[Double]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: gridCols), count: gridRows)
        
        // 各GPSポイントをグリッドに配置
        for point in gpsData.points {
            guard let fieldCoord = field.convertToFieldCoordinate(
                CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            ) else {
                continue
            }
            
            // isFlipped の場合はフィールド中心を軸に180度回転 (x, y) → (width-x, length-y)
            let fx = isFlipped ? field.dimensions.width  - fieldCoord.x : fieldCoord.x
            let fy = isFlipped ? field.dimensions.length - fieldCoord.y : fieldCoord.y

            // フィールド座標をグリッドインデックスに変換
            let normalizedX = fx / field.dimensions.width
            let normalizedY = fy / field.dimensions.length

            let col = Int(normalizedX * Double(gridCols)).clamped(to: 0..<gridCols)
            let row = Int(normalizedY * Double(gridRows)).clamped(to: 0..<gridRows)

            // ガウシアンカーネルで周辺セルにも拡散
            let sigma = 1.5
            let kernelRadius = 4
            for dr in -kernelRadius...kernelRadius {
                for dc in -kernelRadius...kernelRadius {
                    let r = row + dr
                    let c = col + dc
                    guard r >= 0 && r < gridRows && c >= 0 && c < gridCols else { continue }
                    let distance = sqrt(Double(dr * dr + dc * dc))
                    let weight = exp(-(distance * distance) / (2.0 * sigma * sigma))
                    grid[r][c] += weight
                }
            }
        }

        // 対数正規化（最大値を1.0に）
        let maxValue = grid.flatMap { $0 }.max() ?? 1.0
        if maxValue > 0 {
            let logMax = log(maxValue + 1)
            for row in 0..<gridRows {
                for col in 0..<gridCols {
                    grid[row][col] = log(grid[row][col] + 1) / logMax
                }
            }
        }
        
        return grid
    }
}

/// ヒートマップグリッドを描画
struct HeatmapGridView: View {
    let heatmap: [[Double]]
    let rows: Int
    let cols: Int
    let size: CGSize
    let field: Field
    
    var body: some View {
        Canvas { context, size in
            let padding: CGFloat = 20
            let availableWidth = size.width - padding * 2
            let availableHeight = size.height - padding * 2
            
            // フィールドのアスペクト比（長辺が縦になるよう自動計算）
            let fieldRatio = autoFieldRatio(field.dimensions)
            
            var drawWidth = availableWidth
            var drawHeight = availableWidth / fieldRatio
            
            if drawHeight > availableHeight {
                drawHeight = availableHeight
                drawWidth = drawHeight * fieldRatio
            }
            
            let offsetX = (size.width - drawWidth) / 2
            let offsetY = (size.height - drawHeight) / 2
            
            let cellWidth = drawWidth / CGFloat(cols)
            let cellHeight = drawHeight / CGFloat(rows)
            
            for row in 0..<rows {
                for col in 0..<cols {
                    let intensity = heatmap[row][col]
                    
                    // 強度に応じた色（透明 → 赤）
                    if intensity > 0 {
                        let color = heatmapColor(for: intensity)
                        let rect = CGRect(
                            x: offsetX + CGFloat(col) * cellWidth,
                            y: offsetY + CGFloat(rows - 1 - row) * cellHeight,
                            width: cellWidth,
                            height: cellHeight
                        )
                        
                        context.fill(Path(rect), with: .color(color))
                    }
                }
            }
        }
    }
    
    /// ヒートマップの色を計算（青→緑→黄→赤、強度に比例した不透明度）
    private func heatmapColor(for intensity: Double) -> Color {
        let opacity = intensity * 0.85
        if intensity < 0.25 {
            let t = intensity / 0.25
            return Color(red: 0, green: 0, blue: 1 - t * 0.5).opacity(opacity)
        } else if intensity < 0.5 {
            let t = (intensity - 0.25) / 0.25
            return Color(red: 0, green: t, blue: 0.5).opacity(opacity)
        } else if intensity < 0.75 {
            let t = (intensity - 0.5) / 0.25
            return Color(red: t, green: 1, blue: 0).opacity(opacity)
        } else {
            let t = (intensity - 0.75) / 0.25
            return Color(red: 1, green: 1 - t, blue: 0).opacity(opacity)
        }
    }
}

// MARK: - Third Lines Overlay

/// ヒートマップ上にサード境界線とラベルを描画するオーバーレイ
private struct ThirdLinesOverlay: View {
    let thirdRatios: (defensive: Double, middle: Double, attacking: Double)
    let field: Field
    let size: CGSize

    var body: some View {
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

        // fy → Y方向（縦）にマッピングされるため境界は水平破線
        let b1y = offsetY + drawHeight / 3
        let b2y = offsetY + drawHeight * 2 / 3
        let midX = offsetX + drawWidth / 2

        return ZStack {
            Canvas { context, _ in
                for y in [b1y, b2y] {
                    var path = Path()
                    path.move(to: CGPoint(x: offsetX, y: y))
                    path.addLine(to: CGPoint(x: offsetX + drawWidth, y: y))
                    context.stroke(
                        path,
                        with: .color(.white.opacity(0.8)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                    )
                }
            }

            Text(String(format: "守備\n%.0f%%", thirdRatios.defensive))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .position(x: midX, y: offsetY + drawHeight / 6)

            Text(String(format: "中盤\n%.0f%%", thirdRatios.middle))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .position(x: midX, y: offsetY + drawHeight / 2)

            Text(String(format: "攻撃\n%.0f%%", thirdRatios.attacking))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.6), radius: 2)
                .position(x: midX, y: offsetY + drawHeight * 5 / 6)
        }
    }
}

// MARK: - Field Ratio Helper

/// 長辺が縦に表示されるよう fieldRatio を自動計算
/// fieldRatio < 1 → drawHeight > drawWidth（縦長）
fileprivate func autoFieldRatio(_ dimensions: Field.FieldDimensions) -> CGFloat {
    let longer  = max(dimensions.length, dimensions.width)
    let shorter = min(dimensions.length, dimensions.width)
    return shorter / longer
}

// MARK: - Helper Extensions

extension Int {
    func clamped(to range: Range<Int>) -> Int {
        return Swift.min(Swift.max(self, range.lowerBound), range.upperBound - 1)
    }
}

#Preview {
    FieldHeatmapView(
        gpsData: MockData.generateMockGPSData(sessionId: "preview", pointCount: 300),
        field: MockData.mockField,
        isFlipped: false
    )
    .frame(height: 400)
}
