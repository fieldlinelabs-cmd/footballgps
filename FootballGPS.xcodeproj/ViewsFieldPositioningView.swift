//
//  FieldPositioningView.swift
//  FootballGPS
//
//  Created on 2026/03/01.
//

import SwiftUI
import CoreLocation

/// フィールド上に選手の移動軌跡を表示するビュー
struct FieldPositioningView: View {
    let gpsData: GPSData
    let field: Field
    
    @State private var fieldPoints: [CGPoint] = []
    @State private var showSpeed = false
    
    var body: some View {
        VStack(spacing: 8) {
            // メイン表示
            GeometryReader { geometry in
                ZStack {
                    // フィールド背景
                    fieldBackground
                    
                    // フィールドライン
                    fieldLines(in: geometry.size)
                    
                    // 移動軌跡
                    if !fieldPoints.isEmpty {
                        trajectoryPath(in: geometry.size)
                        
                        // スタート地点
                        startMarker(in: geometry.size)
                        
                        // ゴール地点
                        endMarker(in: geometry.size)
                    } else {
                        ProgressView("軌跡を計算中...")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(UIColor.systemGray6))
                .cornerRadius(12)
            }
            
            // オプション切り替え
            Toggle("速度で色分け", isOn: $showSpeed)
                .font(.caption)
                .padding(.horizontal)
        }
        .padding(.horizontal)
        .task {
            await convertToFieldCoordinates()
        }
    }
    
    // MARK: - Field Background
    
    private var fieldBackground: some View {
        Rectangle()
            .fill(Color.green.opacity(0.3))
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
    
    // MARK: - Trajectory Path
    
    private func trajectoryPath(in size: CGSize) -> some View {
        Canvas { context, canvasSize in
            guard fieldPoints.count >= 2 else { return }
            
            let scaleX = size.width / field.dimensions.width
            let scaleY = size.height / field.dimensions.length
            
            if showSpeed {
                // 速度に応じて色分け
                for i in 0..<(fieldPoints.count - 1) {
                    let start = fieldPoints[i]
                    let end = fieldPoints[i + 1]
                    
                    let scaledStart = CGPoint(x: start.x * scaleX, y: start.y * scaleY)
                    let scaledEnd = CGPoint(x: end.x * scaleX, y: end.y * scaleY)
                    
                    var path = Path()
                    path.move(to: scaledStart)
                    path.addLine(to: scaledEnd)
                    
                    // 速度から色を決定
                    let speed = i < gpsData.points.count ? gpsData.points[i].speed : 0
                    let color = speedColor(for: speed)
                    
                    context.stroke(path, with: .color(color), lineWidth: 3)
                }
            } else {
                // 単色の軌跡
                var path = Path()
                let firstScaled = CGPoint(
                    x: fieldPoints[0].x * scaleX,
                    y: fieldPoints[0].y * scaleY
                )
                path.move(to: firstScaled)
                
                for point in fieldPoints.dropFirst() {
                    let scaledPoint = CGPoint(x: point.x * scaleX, y: point.y * scaleY)
                    path.addLine(to: scaledPoint)
                }
                
                context.stroke(path, with: .color(.blue), lineWidth: 3)
            }
        }
    }
    
    // MARK: - Start/End Markers
    
    private func startMarker(in size: CGSize) -> some View {
        let scaleX = size.width / field.dimensions.width
        let scaleY = size.height / field.dimensions.length
        
        guard let firstPoint = fieldPoints.first else {
            return AnyView(EmptyView())
        }
        
        let position = CGPoint(
            x: firstPoint.x * scaleX,
            y: firstPoint.y * scaleY
        )
        
        return AnyView(
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .position(position)
        )
    }
    
    private func endMarker(in size: CGSize) -> some View {
        let scaleX = size.width / field.dimensions.width
        let scaleY = size.height / field.dimensions.length
        
        guard let lastPoint = fieldPoints.last else {
            return AnyView(EmptyView())
        }
        
        let position = CGPoint(
            x: lastPoint.x * scaleX,
            y: lastPoint.y * scaleY
        )
        
        return AnyView(
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .position(position)
        )
    }
    
    // MARK: - Helper Functions
    
    private func convertToFieldCoordinates() async {
        let points = await Task.detached {
            gpsData.points.compactMap { point -> CGPoint? in
                let coordinate = CLLocationCoordinate2D(
                    latitude: point.latitude,
                    longitude: point.longitude
                )
                return field.convertToFieldCoordinate(coordinate)
            }
        }.value
        
        await MainActor.run {
            self.fieldPoints = points
        }
    }
    
    private func speedColor(for speed: Double) -> Color {
        // 速度に応じた色(緑 -> 黄 -> 赤)
        // 0 m/s: 青, 3 m/s: 黄, 6+ m/s: 赤
        if speed < 1.5 {
            return .blue
        } else if speed < 3.0 {
            let t = (speed - 1.5) / 1.5
            return Color(
                red: t,
                green: 1.0,
                blue: 1.0 - t
            )
        } else if speed < 5.0 {
            let t = (speed - 3.0) / 2.0
            return Color(
                red: 1.0,
                green: 1.0 - t,
                blue: 0.0
            )
        } else {
            return .red
        }
    }
}

#Preview {
    FieldPositioningView(
        gpsData: MockData.generateMockGPSData(sessionId: "test"),
        field: MockData.mockField
    )
    .frame(height: 600)
}
