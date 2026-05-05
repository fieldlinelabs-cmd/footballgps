//
//  ContentView.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            SessionsListView()
                .tabItem {
                    Label("セッション", systemImage: "list.bullet")
                }
            
            FieldsListView()
                .tabItem {
                    Label("フィールド", systemImage: "map")
                }
            
            TeamView()
                .tabItem {
                    Label("チーム", systemImage: "person.3.fill")
                }
            
            // DEBUG条件を一時的に外してテスト
            DebugTestView()
                .tabItem {
                    Label("テスト", systemImage: "hammer.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("設定", systemImage: "gear")
                }
        }
    }
}

// MARK: - Debug Test View (シミュレーター用)

// DEBUG条件を一時的に外してテスト
// #if DEBUG
import CoreLocation

struct DebugTestView: View {
    @StateObject private var dataManager = SessionDataManager.shared
    @StateObject private var fieldManager = FieldManager.shared
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("シミュレーターでテストデータを生成できます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("デバッグモード")
                }
                
                Section {
                    Button {
                        generateQuickTestData()
                    } label: {
                        Label("テストデータを生成", systemImage: "plus.circle.fill")
                    }
                    
                    if !dataManager.sessions.isEmpty {
                        Text("セッション数: \(dataManager.sessions.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !fieldManager.fields.isEmpty {
                        Text("フィールド数: \(fieldManager.fields.count)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("クイック生成")
                }
                
                Section {
                    NavigationLink {
                        DebugGPSLogView()
                    } label: {
                        Label("GPSログを確認", systemImage: "location.fill")
                    }
                } header: {
                    Text("デバッグツール")
                }
                
                Section {
                    Button(role: .destructive) {
                        dataManager.clearAllData()
                        fieldManager.clearAllFields()
                        alertMessage = "すべてのデータを削除しました"
                        showAlert = true
                    } label: {
                        Label("すべてのデータをクリア", systemImage: "trash.fill")
                    }
                } header: {
                    Text("データ管理")
                }
            }
            .navigationTitle("デバッグ")
            .alert("完了", isPresented: $showAlert) {
                Button("OK") {}
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private func generateQuickTestData() {
        // フィールドを作成
        if fieldManager.fields.isEmpty {
            let field = createTestField()
            fieldManager.addField(field)
            fieldManager.selectField(field.id)
        }
        
        guard let field = fieldManager.fields.first else { return }
        
        // セッションを作成
        let sessionId = UUID().uuidString
        let gpsData = generateTestGPSData(sessionId: sessionId, field: field)
        
        var totalDistance = 0.0
        var maxSpeed = 0.0
        
        for i in 1..<gpsData.points.count {
            let prev = gpsData.points[i - 1]
            let curr = gpsData.points[i]
            let prevLoc = CLLocation(latitude: prev.latitude, longitude: prev.longitude)
            let currLoc = CLLocation(latitude: curr.latitude, longitude: curr.longitude)
            totalDistance += prevLoc.distance(from: currLoc)
            maxSpeed = max(maxSpeed, curr.speed)
        }
        
        var session = TrainingSession(
            id: sessionId,
            userId: "test_user",
            name: "テストセッション \(dataManager.sessions.count + 1)",
            date: Date(),
            duration: 1800,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            avgSpeed: totalDistance / 1800
        )
        session.fieldId = field.id
        
        dataManager.saveSession(session, gpsData: gpsData)
        
        alertMessage = "テストデータを生成しました!\n距離: \(Int(totalDistance))m"
        showAlert = true
    }
    
    private func createTestField() -> Field {
        let baseLat = 35.681236
        let baseLon = 139.767125
        let metersPerDegreeLat = 111320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(baseLat * .pi / 180)
        let latDelta = 105.0 / metersPerDegreeLat
        let lonDelta = 68.0 / metersPerDegreeLon
        
        return Field(
            teamId: "test_team",
            name: "テストフィールド",
            createdBy: "test_user",
            corners: Field.FieldCorners(
                topLeft: Field.Coordinate(latitude: baseLat + latDelta / 2, longitude: baseLon - lonDelta / 2),
                topRight: Field.Coordinate(latitude: baseLat + latDelta / 2, longitude: baseLon + lonDelta / 2),
                bottomRight: Field.Coordinate(latitude: baseLat - latDelta / 2, longitude: baseLon + lonDelta / 2),
                bottomLeft: Field.Coordinate(latitude: baseLat - latDelta / 2, longitude: baseLon - lonDelta / 2)
            ),
            dimensions: .standard
        )
    }
    
    private func generateTestGPSData(sessionId: String, field: Field) -> GPSData {
        var points: [GPSPoint] = []
        let centerLat = (field.corners.topLeft.latitude + field.corners.bottomRight.latitude) / 2
        let centerLon = (field.corners.topLeft.longitude + field.corners.bottomRight.longitude) / 2
        let latRange = abs(field.corners.bottomRight.latitude - field.corners.topLeft.latitude)
        let lonRange = abs(field.corners.topRight.longitude - field.corners.topLeft.longitude)
        
        var currentLat = centerLat
        var currentLon = centerLon
        var direction: Double = 0
        var speed: Double = 0
        
        for i in 0..<450 {
            let timestamp = Date().addingTimeInterval(Double(i) * 2)
            
            if i % 5 == 0 {
                direction += Double.random(in: -0.5...0.5)
                speed = max(0, min(7, speed + Double.random(in: -2...3)))
            }
            
            let distance = speed * 2.0
            let metersPerDegreeLat = 111320.0
            let metersPerDegreeLon = metersPerDegreeLat * cos(currentLat * .pi / 180)
            
            currentLat += (cos(direction) * distance) / metersPerDegreeLat
            currentLon += (sin(direction) * distance) / metersPerDegreeLon
            
            let minLat = min(field.corners.topLeft.latitude, field.corners.bottomLeft.latitude)
            let maxLat = max(field.corners.topLeft.latitude, field.corners.bottomLeft.latitude)
            let minLon = min(field.corners.topLeft.longitude, field.corners.topRight.longitude)
            let maxLon = max(field.corners.topLeft.longitude, field.corners.topRight.longitude)
            
            if currentLat < minLat || currentLat > maxLat {
                direction = -.pi - direction
                currentLat = max(minLat, min(maxLat, currentLat))
            }
            if currentLon < minLon || currentLon > maxLon {
                direction = -direction
                currentLon = max(minLon, min(maxLon, currentLon))
            }
            
            points.append(GPSPoint(
                timestamp: timestamp,
                latitude: currentLat,
                longitude: currentLon,
                speed: speed,
                altitude: 10,
                horizontalAccuracy: 10
            ))
        }
        
        return GPSData(sessionId: sessionId, points: points)
    }
}
// #endif

#Preview {
    ContentView()
}
// MARK: - Debug GPS Log View

struct DebugGPSLogView: View {
    @StateObject private var dataManager = SessionDataManager.shared
    
    var body: some View {
        List {
            if dataManager.sessions.isEmpty {
                Section {
                    Text("セッションがありません")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(dataManager.sessions) { session in
                    Section {
                        if let gpsData = dataManager.getGPSData(for: session.id) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("GPSポイント数: \(gpsData.points.count)")
                                    .font(.headline)
                                
                                if gpsData.points.isEmpty {
                                    Text("⚠️ GPSポイントが記録されていません")
                                        .foregroundStyle(.orange)
                                } else {
                                    Text("✅ GPSデータあり")
                                        .foregroundStyle(.green)
                                    
                                    // 地図で表示ボタン
                                    NavigationLink {
                                        GPSMapDebugView(gpsData: gpsData, sessionName: session.name)
                                    } label: {
                                        Label("地図で確認", systemImage: "map.fill")
                                            .font(.subheadline)
                                    }
                                    .padding(.vertical, 4)
                                    
                                    Divider()
                                    
                                    // 最初と最後のポイントを表示
                                    if let first = gpsData.points.first {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("最初の点:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("  緯度: \(String(format: "%.6f", first.latitude))")
                                                .font(.caption2)
                                            Text("  経度: \(String(format: "%.6f", first.longitude))")
                                                .font(.caption2)
                                            Text("  速度: \(String(format: "%.1f", first.speed)) m/s")
                                                .font(.caption2)
                                        }
                                    }
                                    
                                    if let last = gpsData.points.last, gpsData.points.count > 1 {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("最後の点:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("  緯度: \(String(format: "%.6f", last.latitude))")
                                                .font(.caption2)
                                            Text("  経度: \(String(format: "%.6f", last.longitude))")
                                                .font(.caption2)
                                            Text("  速度: \(String(format: "%.1f", last.speed)) m/s")
                                                .font(.caption2)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("❌ GPSデータが見つかりません")
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text(session.name)
                    }
                }
            }
        }
        .navigationTitle("GPSログ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - GPS Map Debug View
import MapKit

struct GPSMapDebugView: View {
    let gpsData: GPSData
    let sessionName: String
    
    @State private var region: MKCoordinateRegion
    @State private var selectedPointIndex: Int?
    @State private var showFieldOverlay = true
    @StateObject private var fieldManager = FieldManager.shared
    
    // 使用するフィールド
    private var field: Field? {
        fieldManager.getSelectedField() ?? fieldManager.fields.first
    }
    
    init(gpsData: GPSData, sessionName: String) {
        self.gpsData = gpsData
        self.sessionName = sessionName
        
        // 初期リージョンを計算
        if let firstPoint = gpsData.points.first {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: firstPoint.latitude,
                    longitude: firstPoint.longitude
                ),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 35.681236, longitude: 139.767125),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 地図
            ZStack {
                Map(coordinateRegion: $region, annotationItems: annotationItems) { item in
                    MapMarker(coordinate: item.coordinate, tint: item.color)
                }
                
                // フィールドの枠をオーバーレイ
                if showFieldOverlay, let field = field {
                    GeometryReader { geometry in
                        FieldOverlayView(
                            field: field,
                            region: region,
                            size: geometry.size
                        )
                    }
                }
            }
            .frame(height: 400)
            .onChange(of: showFieldOverlay) { newValue in
                if newValue {
                    // フィールド表示ONの場合、GPSとフィールド両方を含む範囲に調整
                    fitMapToPointsAndField()
                }
            }
            
            // 統計情報
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("総ポイント数")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(gpsData.points.count)点")
                            .font(.title3)
                            .fontWeight(.bold)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("範囲")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(rangeText)
                            .font(.caption2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                // フィールド表示切り替え
                if field != nil {
                    Divider()
                    
                    HStack {
                        Image(systemName: "square.dashed")
                            .foregroundStyle(.blue)
                        
                        Text("フィールドの枠を表示")
                            .font(.subheadline)
                        
                        Spacer()
                        
                        Toggle("", isOn: $showFieldOverlay)
                            .labelsHidden()
                    }
                    
                    if let field = field {
                        Text("使用フィールド: \(field.name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Divider()
                
                // ポイント一覧（最新10件）
                VStack(alignment: .leading, spacing: 8) {
                    Text("最新10ポイント")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    ForEach(Array(gpsData.points.suffix(10).enumerated()), id: \.offset) { index, point in
                        let globalIndex = gpsData.points.count - 10 + index
                        HStack(spacing: 8) {
                            Circle()
                                .fill(colorForPoint(at: globalIndex))
                                .frame(width: 8, height: 8)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("#\(globalIndex + 1)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("\(String(format: "%.6f", point.latitude)), \(String(format: "%.6f", point.longitude))")
                                    .font(.caption2)
                            }
                            
                            Spacer()
                            
                            Text("\(String(format: "%.1f", point.speed)) m/s")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding()
            
            Spacer()
            
            // 地図を調整ボタン
            HStack(spacing: 12) {
                Button {
                    fitMapToPoints()
                } label: {
                    Label("全体を表示", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                
                Button {
                    if let first = gpsData.points.first {
                        region.center = CLLocationCoordinate2D(
                            latitude: first.latitude,
                            longitude: first.longitude
                        )
                    }
                } label: {
                    Label("開始地点", systemImage: "location.fill")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .tint(.green)
            }
            .padding()
        }
        .navigationTitle(sessionName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            fitMapToPoints()
        }
    }
    
    // アノテーション用のアイテム
    private var annotationItems: [GPSAnnotationItem] {
        var items: [GPSAnnotationItem] = []
        
        for (index, point) in gpsData.points.enumerated() {
            let isFirst = index == 0
            let isLast = index == gpsData.points.count - 1
            
            items.append(GPSAnnotationItem(
                id: index,
                coordinate: CLLocationCoordinate2D(
                    latitude: point.latitude,
                    longitude: point.longitude
                ),
                color: colorForPoint(at: index),
                isSpecial: isFirst || isLast
            ))
        }
        
        return items
    }
    
    // ポイントの色を決定
    private func colorForPoint(at index: Int) -> Color {
        if index == 0 {
            return .green // 開始地点
        } else if index == gpsData.points.count - 1 {
            return .red // 終了地点
        } else {
            let ratio = Double(index) / Double(max(gpsData.points.count - 1, 1))
            return Color(
                red: ratio,
                green: 0.5,
                blue: 1.0 - ratio
            )
        }
    }
    
    // 範囲テキスト
    private var rangeText: String {
        guard !gpsData.points.isEmpty else { return "N/A" }
        
        let lats = gpsData.points.map { $0.latitude }
        let lons = gpsData.points.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        return """
        緯度: \(String(format: "%.6f", minLat)) - \(String(format: "%.6f", maxLat))
        経度: \(String(format: "%.6f", minLon)) - \(String(format: "%.6f", maxLon))
        """
    }
    
    // 全ポイントが見えるように地図を調整
    private func fitMapToPoints() {
        guard !gpsData.points.isEmpty else { return }
        
        let lats = gpsData.points.map { $0.latitude }
        let lons = gpsData.points.map { $0.longitude }
        
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        
        let spanLat = max((maxLat - minLat) * 1.2, 0.001) // 20%のマージン
        let spanLon = max((maxLon - minLon) * 1.2, 0.001)
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }
    
    // GPSポイントとフィールド両方を含むように地図を調整
    private func fitMapToPointsAndField() {
        guard !gpsData.points.isEmpty, let field = field else {
            fitMapToPoints()
            return
        }
        
        // GPSポイントの範囲
        let gpsLats = gpsData.points.map { $0.latitude }
        let gpsLons = gpsData.points.map { $0.longitude }
        
        // フィールドの範囲
        let fieldLats = [
            field.corners.topLeft.latitude,
            field.corners.topRight.latitude,
            field.corners.bottomRight.latitude,
            field.corners.bottomLeft.latitude
        ]
        let fieldLons = [
            field.corners.topLeft.longitude,
            field.corners.topRight.longitude,
            field.corners.bottomRight.longitude,
            field.corners.bottomLeft.longitude
        ]
        
        // 両方を含む範囲を計算
        let allLats = gpsLats + fieldLats
        let allLons = gpsLons + fieldLons
        
        let minLat = allLats.min() ?? 0
        let maxLat = allLats.max() ?? 0
        let minLon = allLons.min() ?? 0
        let maxLon = allLons.max() ?? 0
        
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        
        let spanLat = max((maxLat - minLat) * 1.3, 0.001) // 30%のマージン（フィールドも含むため広めに）
        let spanLon = max((maxLon - minLon) * 1.3, 0.001)
        
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon),
            span: MKCoordinateSpan(latitudeDelta: spanLat, longitudeDelta: spanLon)
        )
    }
}

// GPS地図用のアノテーションアイテム
struct GPSAnnotationItem: Identifiable {
    let id: Int
    let coordinate: CLLocationCoordinate2D
    let color: Color
    let isSpecial: Bool
}

// MARK: - Field Overlay View

struct FieldOverlayView: View {
    let field: Field
    let region: MKCoordinateRegion
    let size: CGSize
    
    var body: some View {
        Canvas { context, size in
            // フィールドの4隅の座標を画面座標に変換
            let topLeft = convertToScreenCoordinate(field.corners.topLeft.clLocationCoordinate, in: size)
            let topRight = convertToScreenCoordinate(field.corners.topRight.clLocationCoordinate, in: size)
            let bottomRight = convertToScreenCoordinate(field.corners.bottomRight.clLocationCoordinate, in: size)
            let bottomLeft = convertToScreenCoordinate(field.corners.bottomLeft.clLocationCoordinate, in: size)
            
            // デバッグ: 座標情報を出力
            print("📍 フィールドオーバーレイ座標:")
            print("  左上: \(field.corners.topLeft.latitude), \(field.corners.topLeft.longitude) → \(topLeft?.debugDescription ?? "nil")")
            print("  右上: \(field.corners.topRight.latitude), \(field.corners.topRight.longitude) → \(topRight?.debugDescription ?? "nil")")
            print("  右下: \(field.corners.bottomRight.latitude), \(field.corners.bottomRight.longitude) → \(bottomRight?.debugDescription ?? "nil")")
            print("  左下: \(field.corners.bottomLeft.latitude), \(field.corners.bottomLeft.longitude) → \(bottomLeft?.debugDescription ?? "nil")")
            print("  地図範囲: center=\(region.center.latitude),\(region.center.longitude) span=\(region.span.latitudeDelta),\(region.span.longitudeDelta)")
            
            // 4隅にマーカーを描画（個別に）
            if let topLeft = topLeft {
                drawCornerMarker(context: context, at: topLeft, label: "左上", color: .green)
            }
            if let topRight = topRight {
                drawCornerMarker(context: context, at: topRight, label: "右上", color: .blue)
            }
            if let bottomRight = bottomRight {
                drawCornerMarker(context: context, at: bottomRight, label: "右下", color: .red)
            }
            if let bottomLeft = bottomLeft {
                drawCornerMarker(context: context, at: bottomLeft, label: "左下", color: .orange)
            }
            
            // 4つすべての座標が有効な場合のみ枠線を描画
            if let topLeft = topLeft,
               let topRight = topRight,
               let bottomRight = bottomRight,
               let bottomLeft = bottomLeft {
                
                // フィールドの枠を描画
                var path = Path()
                path.move(to: topLeft)
                path.addLine(to: topRight)
                path.addLine(to: bottomRight)
                path.addLine(to: bottomLeft)
                path.closeSubpath()
                
                // 枠線を描画（赤色、点線）
                context.stroke(
                    path,
                    with: .color(.red),
                    style: StrokeStyle(
                        lineWidth: 3,
                        dash: [10, 5]
                    )
                )
                
                // 半透明の塗りつぶし
                context.fill(
                    path,
                    with: .color(.red.opacity(0.1))
                )
            } else {
                print("⚠️ 4隅のいずれかが画面外のため、枠線を描画できません")
            }
        }
    }
    
    // GPS座標を画面座標に変換
    private func convertToScreenCoordinate(_ coordinate: CLLocationCoordinate2D, in size: CGSize) -> CGPoint? {
        // リージョンの範囲を計算
        let minLat = region.center.latitude - region.span.latitudeDelta / 2
        let maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2
        let maxLon = region.center.longitude + region.span.longitudeDelta / 2
        
        // デバッグ: 範囲チェック
        let isInRange = coordinate.latitude >= minLat && coordinate.latitude <= maxLat &&
                       coordinate.longitude >= minLon && coordinate.longitude <= maxLon
        
        if !isInRange {
            print("  → 座標が範囲外: lat \(coordinate.latitude) (範囲: \(minLat)~\(maxLat)), lon \(coordinate.longitude) (範囲: \(minLon)~\(maxLon))")
            // 範囲外でもポイントは表示する（クランプする）
        }
        
        // 正規化された座標（0.0 ~ 1.0）- 範囲外でもクランプして表示
        let normalizedX = min(max((coordinate.longitude - minLon) / (maxLon - minLon), 0), 1)
        let normalizedY = min(max(1.0 - (coordinate.latitude - minLat) / (maxLat - minLat), 0), 1) // Y軸は反転
        
        // 画面座標に変換
        let x = normalizedX * size.width
        let y = normalizedY * size.height
        
        return CGPoint(x: x, y: y)
    }
    
    // 隅のマーカーを描画
    private func drawCornerMarker(context: GraphicsContext, at point: CGPoint, label: String, color: Color) {
        // 円を描画
        let circle = Path(ellipseIn: CGRect(
            x: point.x - 8,
            y: point.y - 8,
            width: 16,
            height: 16
        ))
        
        context.fill(circle, with: .color(color))
        context.stroke(circle, with: .color(.white), lineWidth: 3)
        
        // ラベルを描画
        let text = Text(label)
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white)
        
        context.draw(text, at: CGPoint(x: point.x, y: point.y + 20))
    }
}


