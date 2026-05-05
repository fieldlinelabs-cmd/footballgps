//
//  MapFieldSetupView.swift
//  FootballGPS
//
//  Created on 2025/01/08.
//

import SwiftUI
import MapKit

/// 地図でフィールドの4隅を設定する画面
struct MapFieldSetupView: View {
    @Binding var corners: Field.FieldCorners?
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
    )
    
    @State private var topLeft: CLLocationCoordinate2D?
    @State private var topRight: CLLocationCoordinate2D?
    @State private var bottomRight: CLLocationCoordinate2D?
    @State private var bottomLeft: CLLocationCoordinate2D?
    
    @State private var selectedCorner: CornerType?
    @State private var showingInstructions = true
    @State private var searchText = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var isSearching = false
    @State private var mapType: MKMapType = .standard
    
    enum CornerType: String, CaseIterable {
        case topLeft = "左上"
        case topRight = "右上"
        case bottomRight = "右下"
        case bottomLeft = "左下"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // 地図（カスタムビュー）
                MapViewRepresentable(
                    region: $region,
                    mapType: $mapType,
                    annotations: annotations,
                    fieldPolygon: fieldPolygonCoordinates
                )
                .edgesIgnoringSafeArea(.all)
                
                // 検索バーと結果
                VStack {
                    // 検索バー
                    HStack {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            
                            TextField("住所やランドマークを検索", text: $searchText)
                                .textFieldStyle(.plain)
                                .onSubmit {
                                    performSearch()
                                }
                            
                            if !searchText.isEmpty {
                                Button {
                                    searchText = ""
                                    searchResults = []
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        
                        if isSearching {
                            ProgressView()
                                .padding(.horizontal, 4)
                        }
                    }
                    .padding()
                    
                    // 検索結果
                    if !searchResults.isEmpty {
                        ScrollView {
                            VStack(spacing: 0) {
                                ForEach(searchResults, id: \.self) { item in
                                    Button {
                                        selectSearchResult(item)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(item.name ?? "")
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                            
                                            if let address = item.placemark.title {
                                                Text(address)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                        .background(.ultraThinMaterial)
                                    }
                                    
                                    Divider()
                                }
                            }
                            .cornerRadius(10)
                        }
                        .frame(maxHeight: 200)
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                
                // 設定コントロール
                VStack {
                    Spacer()
                    
                    VStack(spacing: 12) {
                        // 説明
                        if showingInstructions {
                            Text("地図の中心に合わせてタップ")
                                .font(.headline)
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                        
                        // 4隅が揃ったら補正プレビューを案内
                        if allCornersSet {
                            Text("青枠：直角補正後のフィールド")
                                .font(.caption)
                                .foregroundStyle(.blue)
                                .padding(.horizontal)
                                .padding(.vertical, 6)
                                .background(.ultraThinMaterial)
                                .cornerRadius(8)
                        }
                        
                        // 4隅選択ボタン
                        HStack(spacing: 12) {
                            ForEach(CornerType.allCases, id: \.self) { corner in
                                cornerButton(for: corner)
                            }
                        }
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        
                        // 現在地ボタンと地図タイプ切り替え
                        HStack(spacing: 12) {
                            // 地図タイプ切り替えボタン
                            Button {
                                toggleMapType()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: mapType == .standard ? "map" : "map.fill")
                                        .font(.title3)
                                    Text(mapType == .standard ? "標準" : "航空写真")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.white)
                                .frame(width: 70, height: 50)
                                .background(Color.gray)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            
                            // 現在地ボタン
                            Button {
                                centerOnCurrentLocation()
                            } label: {
                                Image(systemName: "location.fill")
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 50, height: 50)
                                    .background(Color.blue)
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding()
                }
                
                // 中心マーカー
                Image(systemName: "plus")
                    .font(.title)
                    .foregroundStyle(.red)
            }
            .navigationTitle("4隅を設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        saveCorners()
                    }
                    .disabled(!allCornersSet)
                }
            }
            .onAppear {
                loadExistingCorners()
            }
        }
    }
    
    private func cornerButton(for corner: CornerType) -> some View {
        Button {
            setCorner(corner)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isCornerSet(corner) ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isCornerSet(corner) ? .green : .secondary)
                
                Text(corner.rawValue)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var annotations: [MapAnnotation] {
        var items: [MapAnnotation] = []
        
        if let coord = topLeft {
            items.append(MapAnnotation(id: "topLeft", coordinate: coord, color: .green))
        }
        if let coord = topRight {
            items.append(MapAnnotation(id: "topRight", coordinate: coord, color: .blue))
        }
        if let coord = bottomRight {
            items.append(MapAnnotation(id: "bottomRight", coordinate: coord, color: .red))
        }
        if let coord = bottomLeft {
            items.append(MapAnnotation(id: "bottomLeft", coordinate: coord, color: .orange))
        }
        
        return items
    }
    
    /// 4隅が揃っていれば直角補正済みのフィールド境界ポリゴンを返す
    private var fieldPolygonCoordinates: [CLLocationCoordinate2D] {
        guard let tl = topLeft, let tr = topRight,
              let br = bottomRight, let bl = bottomLeft else { return [] }
        let corrected = Field.correctToRectangle(
            topLeft:     Field.Coordinate(from: tl),
            topRight:    Field.Coordinate(from: tr),
            bottomRight: Field.Coordinate(from: br),
            bottomLeft:  Field.Coordinate(from: bl)
        )
        return [
            corrected.topLeft.clLocationCoordinate,
            corrected.topRight.clLocationCoordinate,
            corrected.bottomRight.clLocationCoordinate,
            corrected.bottomLeft.clLocationCoordinate
        ]
    }
    
    private var allCornersSet: Bool {
        topLeft != nil && topRight != nil && bottomRight != nil && bottomLeft != nil
    }
    
    private func isCornerSet(_ corner: CornerType) -> Bool {
        switch corner {
        case .topLeft: return topLeft != nil
        case .topRight: return topRight != nil
        case .bottomRight: return bottomRight != nil
        case .bottomLeft: return bottomLeft != nil
        }
    }
    
    private func setCorner(_ corner: CornerType) {
        let center = region.center
        
        switch corner {
        case .topLeft:
            topLeft = center
        case .topRight:
            topRight = center
        case .bottomRight:
            bottomRight = center
        case .bottomLeft:
            bottomLeft = center
        }
        
        showingInstructions = false
    }
    
    private func centerOnCurrentLocation() {
        // TODO: 現在地を取得して地図をセンタリング
        // 現在はデフォルト位置（東京）
        region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        )
    }
    
    private func loadExistingCorners() {
        guard let existing = corners else { return }
        
        if existing.topLeft.latitude != 0 {
            topLeft = existing.topLeft.clLocationCoordinate
            topRight = existing.topRight.clLocationCoordinate
            bottomRight = existing.bottomRight.clLocationCoordinate
            bottomLeft = existing.bottomLeft.clLocationCoordinate
            
            // 中心を設定済みの座標に移動
            let centerLat = (existing.topLeft.latitude + existing.bottomRight.latitude) / 2
            let centerLon = (existing.topLeft.longitude + existing.bottomRight.longitude) / 2
            region.center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            
            showingInstructions = false
        }
    }
    
    private func saveCorners() {
        guard let tl = topLeft, let tr = topRight, let br = bottomRight, let bl = bottomLeft else {
            return
        }
        
        // 直角に補正して保存
        corners = Field.correctToRectangle(
            topLeft:     Field.Coordinate(from: tl),
            topRight:    Field.Coordinate(from: tr),
            bottomRight: Field.Coordinate(from: br),
            bottomLeft:  Field.Coordinate(from: bl)
        )
        
        dismiss()
    }
    
    // MARK: - Search Functions
    
    /// 地図タイプを切り替え
    private func toggleMapType() {
        switch mapType {
        case .standard:
            mapType = .hybrid
        case .hybrid:
            mapType = .satellite
        case .satellite:
            mapType = .standard
        default:
            mapType = .standard
        }
        
        print("🗺️ 地図タイプ: \(mapType.rawValue)")
    }
    
    /// 検索を実行
    private func performSearch() {
        guard !searchText.isEmpty else { return }
        
        isSearching = true
        searchResults = []
        
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = searchText
        request.region = region
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            isSearching = false
            
            if let error = error {
                print("❌ 検索エラー: \(error.localizedDescription)")
                return
            }
            
            if let response = response {
                searchResults = response.mapItems
                print("✅ 検索結果: \(searchResults.count)件")
            }
        }
    }
    
    /// 検索結果を選択
    private func selectSearchResult(_ item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        
        // 地図を選択した場所に移動
        region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
        )
        
        // 検索結果をクリア
        searchResults = []
        searchText = ""
        
        print("📍 選択: \(item.name ?? ""), 座標: \(coordinate.latitude), \(coordinate.longitude)")
    }
}

// MARK: - Map Annotation

struct MapAnnotation: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let color: Color
}

// MARK: - MapView Representable

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var mapType: MKMapType
    let annotations: [MapAnnotation]
    /// フィールド境界の多角形（順番通りに結んで閉じる）
    var fieldPolygon: [CLLocationCoordinate2D] = []
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.mapType = mapType
        return mapView
    }
    
    func updateUIView(_ mapView: MKMapView, context: Context) {
        // 地図タイプを更新
        if mapView.mapType != mapType {
            mapView.mapType = mapType
        }
        
        // リージョンを更新
        if !mapView.region.isEqual(to: region) {
            mapView.setRegion(region, animated: true)
        }
        
        // アノテーションを更新
        mapView.removeAnnotations(mapView.annotations)
        let mkAnnotations = annotations.map { annotation -> MKPointAnnotation in
            let mkAnnotation = MKPointAnnotation()
            mkAnnotation.coordinate = annotation.coordinate
            mkAnnotation.title = annotation.id
            return mkAnnotation
        }
        mapView.addAnnotations(mkAnnotations)
        
        // フィールド境界オーバーレイを更新
        mapView.removeOverlays(mapView.overlays)
        if fieldPolygon.count >= 3 {
            var coords = fieldPolygon
            let polygon = MKPolygon(coordinates: &coords, count: coords.count)
            mapView.addOverlay(polygon, level: .aboveRoads)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            DispatchQueue.main.async {
                self.parent.region = mapView.region
            }
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = UIColor.systemBlue
                renderer.lineWidth = 2.5
                renderer.fillColor = UIColor.systemBlue.withAlphaComponent(0.12)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "Marker"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            } else {
                annotationView?.annotation = annotation
            }
            
            // 色を設定
            if let title = annotation.title, let titleString = title {
                switch titleString {
                case "topLeft":
                    annotationView?.markerTintColor = .systemGreen
                case "topRight":
                    annotationView?.markerTintColor = .systemBlue
                case "bottomRight":
                    annotationView?.markerTintColor = .systemRed
                case "bottomLeft":
                    annotationView?.markerTintColor = .systemOrange
                default:
                    annotationView?.markerTintColor = .systemPurple
                }
            }
            
            return annotationView
        }
    }
}

// MARK: - Helper Extensions

extension MKCoordinateRegion {
    func isEqual(to other: MKCoordinateRegion, threshold: Double = 0.0001) -> Bool {
        abs(center.latitude - other.center.latitude) < threshold &&
        abs(center.longitude - other.center.longitude) < threshold &&
        abs(span.latitudeDelta - other.span.latitudeDelta) < threshold &&
        abs(span.longitudeDelta - other.span.longitudeDelta) < threshold
    }
}

#Preview {
    MapFieldSetupView(corners: .constant(nil))
}
