//
//  FieldHeatmapView.swift
//  FootballGPS
//
//  Created on 2026/03/01.
//

import SwiftUI

/// フィールド上にヒートマップを表示するビュー
struct FieldHeatmapView: View {
    let gpsData: GPSData
    let field: Field
    
    @State private var heatmapGrid: HeatmapGenerator.HeatmapGrid?
    @State private var showLegend = true
    
    var body: some View {
        VStack(spacing: 8) {
            // ヒートマップ本体
            GeometryReader { geometry in
                ZStack {
                    // フィールド背景
                    fieldBackground
                    
                    // ヒートマップグリッド
                    if let grid = heatmapGrid {
                        heatmapGridView(grid: grid, in: geometry.size)
                    } else {
                        ProgressView("ヒートマップ生成中...")
                    }
                    
                    // フィールドライン
                    fieldLines(in: geometry.size)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
            }
            
            // 凡例
            if showLegend {
                heatmapLegend
                    .transition(.opacity)
            }
        }
        .padding(.horizontal)
        .task {
            // ヒートマップを非同期で生成
            await generateHeatmap()
        }
    }
    
    // MARK: - Field Background
    
    private var fieldBackground: some View {
        Rectangle()
            .fill(Color.green.opacity(0.3))
    }
    
    // MARK: - Heatmap Grid View
    
    private func heatmapGridView(grid: HeatmapGenerator.HeatmapGrid, in size: CGSize) -> some View {
        let cellWidth = size.width / CGFloat(grid.cols)
        let cellHeight = size.height / CGFloat(grid.rows)
        
        return Canvas { context, canvasSize in
            for row in 0..<grid.rows {
                for col in 0..<grid.cols {
                    let intensity = grid.cells[row][col]
                    
                    // 強度がほぼ0の場合はスキップ
                    if intensity < 0.01 { continue }
                    
                    let rect = CGRect(
                        x: CGFloat(col) * cellWidth,
                        y: CGFloat(row) * cellHeight,
                        width: cellWidth,
                        height: cellHeight
                    )
                    
                    let color = HeatmapGenerator.heatmapColor(for: intensity)
                    context.fill(
                        Path(rect),
                        with: .color(color)
                    )
                }
            }
        }
    }
    
    // MARK: - Field Lines
    
    private func fieldLines(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            let lineWidth: CGFloat = 2
            let lineColor = Color.white.opacity(0.6)
            
            // 外枠
            context.stroke(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(lineColor),
                lineWidth: lineWidth
            )
            
            // ハーフウェイライン
            let halfwayY = size.height / 2
            var halfwayPath = Path()
            halfwayPath.move(to: CGPoint(x: 0, y: halfwayY))
            halfwayPath.addLine(to: CGPoint(x: size.width, y: halfwayY))
            context.stroke(halfwayPath, with: .color(lineColor), lineWidth: lineWidth)
            
            // センターサークル
            let centerCircleRadius = size.width * 0.15
            let centerCirclePath = Path(
                ellipseIn: CGRect(
                    x: size.width / 2 - centerCircleRadius,
                    y: halfwayY - centerCircleRadius,
                    width: centerCircleRadius * 2,
                    height: centerCircleRadius * 2
                )
            )
            context.stroke(centerCirclePath, with: .color(lineColor), lineWidth: lineWidth)
            
            // ペナルティエリア（簡易版）
            let penaltyAreaWidth = size.width * 0.6
            let penaltyAreaHeight = size.height * 0.25
            
            // 上側
            let topPenaltyRect = CGRect(
                x: (size.width - penaltyAreaWidth) / 2,
                y: 0,
                width: penaltyAreaWidth,
                height: penaltyAreaHeight
            )
            context.stroke(Path(topPenaltyRect), with: .color(lineColor), lineWidth: lineWidth)
            
            // 下側
            let bottomPenaltyRect = CGRect(
                x: (size.width - penaltyAreaWidth) / 2,
                y: size.height - penaltyAreaHeight,
                width: penaltyAreaWidth,
                height: penaltyAreaHeight
            )
            context.stroke(Path(bottomPenaltyRect), with: .color(lineColor), lineWidth: lineWidth)
        }
    }
    
    // MARK: - Heatmap Legend
    
    private var heatmapLegend: some View {
        HStack(spacing: 12) {
            Text("活動量:")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // カラーバー
            HStack(spacing: 0) {
                ForEach(0..<10) { index in
                    let intensity = Double(index) / 9.0
                    Rectangle()
                        .fill(HeatmapGenerator.heatmapColor(for: intensity))
                        .frame(width: 20, height: 16)
                }
            }
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
            
            HStack(spacing: 4) {
                Text("低")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("高")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 60)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Heatmap Generation
    
    private func generateHeatmap() async {
        // バックグラウンドでヒートマップを生成
        let grid = await Task.detached {
            HeatmapGenerator.generateHeatmap(
                from: gpsData.points,
                field: field,
                gridSize: (rows: 30, cols: 20), // より細かいグリッド
                radius: 2.5
            )
        }.value
        
        await MainActor.run {
            withAnimation {
                self.heatmapGrid = grid
            }
        }
    }
}

#Preview {
    FieldHeatmapView(
        gpsData: MockData.generateMockGPSData(sessionId: "test"),
        field: MockData.mockField
    )
    .frame(height: 600)
}
