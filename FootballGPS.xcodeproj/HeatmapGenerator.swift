//
//  HeatmapGenerator.swift
//  FootballGPS
//
//  Created on 2026/03/01.
//

import Foundation
import CoreLocation
import SwiftUI

/// ヒートマップデータを生成するクラス
class HeatmapGenerator {
    
    /// ヒートマップのグリッドデータ
    struct HeatmapGrid {
        let rows: Int
        let cols: Int
        var cells: [[Double]] // 0.0 - 1.0 の強度値
        
        init(rows: Int, cols: Int) {
            self.rows = rows
            self.cols = cols
            self.cells = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        }
    }
    
    /// GPSポイントからヒートマップグリッドを生成
    /// - Parameters:
    ///   - gpsPoints: GPS座標データ
    ///   - field: フィールド情報
    ///   - gridSize: グリッドサイズ（デフォルト: 20x20）
    ///   - radius: ヒートの影響半径（グリッドセル単位、デフォルト: 2.0）
    /// - Returns: ヒートマップグリッド
    static func generateHeatmap(
        from gpsPoints: [GPSPoint],
        field: Field,
        gridSize: (rows: Int, cols: Int) = (20, 20),
        radius: Double = 2.0
    ) -> HeatmapGrid {
        var grid = HeatmapGrid(rows: gridSize.rows, cols: gridSize.cols)
        
        guard !gpsPoints.isEmpty else { return grid }
        
        // 1. GPS座標をフィールド座標に変換
        let fieldPoints = gpsPoints.compactMap { point -> CGPoint? in
            let coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            return field.convertToFieldCoordinate(coordinate)
        }
        
        guard !fieldPoints.isEmpty else { return grid }
        
        // 2. フィールド座標をグリッド座標に変換して、各セルの密度を計算
        let cellWidth = field.dimensions.width / Double(gridSize.cols)
        let cellHeight = field.dimensions.length / Double(gridSize.rows)
        
        // 各ポイントの重みを計算（滞在時間ベース）
        var weights: [Int: Int] = [:] // グリッドインデックス -> 訪問回数
        
        for point in fieldPoints {
            // フィールド範囲外は除外
            guard point.x >= 0, point.x <= field.dimensions.width,
                  point.y >= 0, point.y <= field.dimensions.length else {
                continue
            }
            
            let col = min(Int(point.x / cellWidth), gridSize.cols - 1)
            let row = min(Int(point.y / cellHeight), gridSize.rows - 1)
            
            let index = row * gridSize.cols + col
            weights[index, default: 0] += 1
        }
        
        // 3. ガウシアンブラーを適用して滑らかなヒートマップにする
        for (index, count) in weights {
            let row = index / gridSize.cols
            let col = index % gridSize.cols
            
            // 影響範囲内のセルに加算
            for r in 0..<gridSize.rows {
                for c in 0..<gridSize.cols {
                    let distance = sqrt(pow(Double(r - row), 2) + pow(Double(c - col), 2))
                    
                    if distance <= radius {
                        // ガウシアン関数で重み付け
                        let sigma = radius / 2.0
                        let weight = exp(-pow(distance, 2) / (2 * pow(sigma, 2)))
                        grid.cells[r][c] += Double(count) * weight
                    }
                }
            }
        }
        
        // 4. 正規化（0.0 - 1.0）
        let maxValue = grid.cells.flatMap { $0 }.max() ?? 1.0
        if maxValue > 0 {
            for r in 0..<gridSize.rows {
                for c in 0..<gridSize.cols {
                    grid.cells[r][c] /= maxValue
                }
            }
        }
        
        return grid
    }
    
    /// 強度値から色を生成（ヒートマップカラー）
    /// - Parameter intensity: 強度値（0.0 - 1.0）
    /// - Returns: 対応する色
    static func heatmapColor(for intensity: Double) -> Color {
        // 透明 -> 青 -> 緑 -> 黄 -> 赤 のグラデーション
        
        if intensity < 0.01 {
            return .clear
        } else if intensity < 0.25 {
            // 青 -> 水色
            let t = intensity / 0.25
            return Color(
                red: 0.0,
                green: t * 0.5,
                blue: 1.0,
                opacity: 0.3 + t * 0.3
            )
        } else if intensity < 0.5 {
            // 水色 -> 緑
            let t = (intensity - 0.25) / 0.25
            return Color(
                red: 0.0,
                green: 0.5 + t * 0.5,
                blue: 1.0 - t * 1.0,
                opacity: 0.6 + t * 0.1
            )
        } else if intensity < 0.75 {
            // 緑 -> 黄色
            let t = (intensity - 0.5) / 0.25
            return Color(
                red: t * 1.0,
                green: 1.0,
                blue: 0.0,
                opacity: 0.7 + t * 0.1
            )
        } else {
            // 黄色 -> 赤
            let t = (intensity - 0.75) / 0.25
            return Color(
                red: 1.0,
                green: 1.0 - t * 1.0,
                blue: 0.0,
                opacity: 0.8 + t * 0.2
            )
        }
    }
}
