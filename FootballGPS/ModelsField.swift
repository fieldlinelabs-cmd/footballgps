//
//  Field.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation
import CoreLocation

/// サッカーフィールドの設定
struct Field: Identifiable, Codable {
    let id: String
    let teamId: String
    var name: String
    let createdBy: String
    let createdAt: Date
    
    // フィールドの4隅の座標
    var corners: FieldCorners
    
    // フィールドの実寸（メートル）
    var dimensions: FieldDimensions
    
    struct FieldCorners: Codable {
        var topLeft: Coordinate
        var topRight: Coordinate
        var bottomRight: Coordinate
        var bottomLeft: Coordinate

        // 4隅の言葉どおりに表示する（docs/フィールド表示向き仕様書.md）:
        // 「左上と右上」「左下と右下」を結ぶ線がゴールライン、「左上と左下」「右上と右下」がタッチライン

        /// 4隅の左右が逆になっているか（登録画面で見た配置の鏡像になっていて、言葉どおりに描けない）。
        /// 北を上・東を右とした平面で、左上→左下の方向が左上→右上の方向から時計回りなら正しい
        var isMirrored: Bool {
            guard topLeft.latitude != 0 else { return false }
            let metersPerLat = 110540.0
            let metersPerLon = 111320.0 * cos(topLeft.latitude * .pi / 180.0)
            let abX = (topRight.longitude - topLeft.longitude) * metersPerLon
            let abY = (topRight.latitude - topLeft.latitude) * metersPerLat
            let adX = (bottomLeft.longitude - topLeft.longitude) * metersPerLon
            let adY = (bottomLeft.latitude - topLeft.latitude) * metersPerLat
            // 外積が正 = 左上→左下が左上→右上から反時計回り
            return abX * adY - abY * adX > 0
        }

        /// ゴールラインの長さ（左上〜右上、メートル）
        var goalLineLength: Double { Field.distance(topLeft, topRight) }

        /// タッチラインの長さ（左上〜左下、メートル）
        var touchLineLength: Double { Field.distance(topLeft, bottomLeft) }

        /// ゴールラインの方がタッチラインより長いか。
        /// 縦横比が `squareTolerance` 未満の正方形に近い場合は、タップ位置のわずかなずれで
        /// 登録できなくなるのを防ぐため false とする
        var isGoalLineLonger: Bool {
            let goal = goalLineLength
            let touch = touchLineLength
            guard goal > touch, touch > 0 else { return false }
            return goal / touch >= Field.squareTolerance
        }
    }

    /// これ未満の縦横比は正方形に近いとみなし、ゴールラインとタッチラインの長さを比べない
    static let squareTolerance = 1.1

    static func distance(_ a: Coordinate, _ b: Coordinate) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }
    
    struct Coordinate: Codable {
        let latitude: Double
        let longitude: Double
        
        init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
        
        init(from location: CLLocationCoordinate2D) {
            self.latitude = location.latitude
            self.longitude = location.longitude
        }
        
        var clLocationCoordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }
    
    struct FieldDimensions: Codable {
        var length: Double // 縦＝タッチラインの長さ（メートル）
        var width: Double // 横＝ゴールラインの長さ（メートル）
        
        static let standard = FieldDimensions(length: 105, width: 68)
    }
    
    init(
        id: String = UUID().uuidString,
        teamId: String,
        name: String,
        createdBy: String,
        createdAt: Date = Date(),
        corners: FieldCorners,
        dimensions: FieldDimensions = .standard
    ) {
        self.id = id
        self.teamId = teamId
        self.name = name
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.corners = corners
        self.dimensions = dimensions
    }
    
    /// GPS座標をフィールド座標（x: 0〜width, y: 0〜length）に変換する。
    /// 原点は左下、x は左下→右下（画面の右）、y は左下→左上（画面の上）。
    /// 登録画面で設定した4隅の位置関係のまま描画するための座標（方位に依存しない2Dベクトル計算）
    func convertToFieldCoordinate(_ gpsCoordinate: CLLocationCoordinate2D) -> CGPoint? {
        guard corners.topLeft.latitude != 0 else { return nil }
        
        let O = corners.bottomLeft.clLocationCoordinate   // 原点（左下）
        let X = corners.bottomRight.clLocationCoordinate  // x 方向（下側のゴールライン）
        let Y = corners.topLeft.clLocationCoordinate      // y 方向（左のタッチライン）
        
        // フラットアース近似：緯度経度をメートル単位のベクトルに変換
        let metersPerLat = 110540.0
        let metersPerLon = 111320.0 * cos(O.latitude * .pi / 180.0)
        
        typealias Vec2 = (x: Double, y: Double)
        func vec(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> Vec2 {
            return (
                x: (to.longitude - from.longitude) * metersPerLon,
                y: (to.latitude - from.latitude) * metersPerLat
            )
        }
        func cross(_ a: Vec2, _ b: Vec2) -> Double { a.x * b.y - a.y * b.x }
        
        let ox = vec(O, X)
        let oy = vec(O, Y)
        let op = vec(O, gpsCoordinate)
        
        // P = O + a*OX + b*OY を解く（平行四辺形座標）
        let denom = cross(ox, oy)
        guard abs(denom) > 1e-10 else { return nil }
        
        let a = cross(op, oy) / denom  // ゴールライン方向の比率（0〜1）
        let b = cross(ox, op) / denom  // タッチライン方向の比率（0〜1）
        
        return CGPoint(x: a * dimensions.width, y: b * dimensions.length)
    }
    
    /// GPS座標がこのフィールド内にあるか判定（点が多角形内にあるか）
    func contains(coordinate: CLLocationCoordinate2D) -> Bool {
        // 4隅が設定されていない場合は判定不可
        guard corners.topLeft.latitude != 0 else {
            return false
        }
        
        // 多角形の頂点（時計回り）
        let vertices = [
            corners.topLeft.clLocationCoordinate,
            corners.topRight.clLocationCoordinate,
            corners.bottomRight.clLocationCoordinate,
            corners.bottomLeft.clLocationCoordinate
        ]
        
        return isPointInPolygon(point: coordinate, polygon: vertices)
    }
    
    /// GPSポイントの配列がこのフィールド内にあるか判定（一致率を返す）
    func matchRate(for points: [GPSPoint]) -> Double {
        guard !points.isEmpty else { return 0.0 }
        
        let matchingPoints = points.filter { point in
            contains(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
        }
        
        return Double(matchingPoints.count) / Double(points.count)
    }
    
    /// 点が多角形内にあるか判定（Ray Casting Algorithm）
    private func isPointInPolygon(point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        
        for i in 0..<polygon.count {
            let xi = polygon[i].longitude
            let yi = polygon[i].latitude
            let xj = polygon[j].longitude
            let yj = polygon[j].latitude
            
            let intersect = ((yi > point.latitude) != (yj > point.latitude))
                && (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi)
            
            if intersect {
                inside.toggle()
            }
            
            j = i
        }
        
        return inside
    }
    
    // MARK: - Field Corners Correction

    /// 4点の生データから直角の長方形に補正する（最小二乗フィット）
    /// - Parameters:
    ///   - topLeft: ユーザーが指定した左上コーナー（近似値）
    ///   - topRight: ユーザーが指定した右上コーナー（近似値）
    ///   - bottomRight: ユーザーが指定した右下コーナー（近似値）
    ///   - bottomLeft: ユーザーが指定した左下コーナー（近似値）
    /// - Returns: 直角に補正された FieldCorners
    static func correctToRectangle(
        topLeft: Field.Coordinate,
        topRight: Field.Coordinate,
        bottomRight: Field.Coordinate,
        bottomLeft: Field.Coordinate
    ) -> FieldCorners {
        let metersPerLat = 110540.0
        let avgLat = (topLeft.latitude + topRight.latitude + bottomRight.latitude + bottomLeft.latitude) / 4
        let metersPerLon = 111320.0 * cos(avgLat * .pi / 180.0)
        
        typealias V2 = (x: Double, y: Double)
        
        // GPS座標 → メートル座標（線形変換）
        func toM(_ c: Field.Coordinate) -> V2 {
            (x: c.longitude * metersPerLon, y: c.latitude * metersPerLat)
        }
        func toC(_ v: V2) -> Field.Coordinate {
            Field.Coordinate(latitude: v.y / metersPerLat, longitude: v.x / metersPerLon)
        }
        func dot(_ a: V2, _ b: V2) -> Double { a.x * b.x + a.y * b.y }
        func normalize(_ v: V2) -> V2 {
            let len = sqrt(v.x * v.x + v.y * v.y)
            return len > 1e-10 ? (v.x / len, v.y / len) : (1, 0)
        }
        
        let p0 = toM(topLeft)
        let p1 = toM(topRight)
        let p2 = toM(bottomRight)
        let p3 = toM(bottomLeft)
        
        // 重心
        let cx = (p0.x + p1.x + p2.x + p3.x) / 4
        let cy = (p0.y + p1.y + p2.y + p3.y) / 4
        
        // ゴールライン方向 u：TL→TR と BL→BR の平均方向
        let u = normalize((
            x: (p1.x - p0.x) + (p2.x - p3.x),
            y: (p1.y - p0.y) + (p2.y - p3.y)
        ))
        
        // タッチライン方向 v：u と直交し、TL→BL 方向に合わせる
        let vTest: V2 = ((p3.x - p0.x) + (p2.x - p1.x), (p3.y - p0.y) + (p2.y - p1.y))
        let vOpt: V2 = (-u.y, u.x)  // u を +90度回転
        let v: V2 = dot(vTest, vOpt) >= 0 ? vOpt : (u.y, -u.x)
        
        // 各点を重心基準の u/v 軸に投影
        let r0: V2 = (p0.x - cx, p0.y - cy)
        let r1: V2 = (p1.x - cx, p1.y - cy)
        let r2: V2 = (p2.x - cx, p2.y - cy)
        let r3: V2 = (p3.x - cx, p3.y - cy)
        
        // ゴールラインの半分：TL=-halfL, TR=+halfL, BR=+halfL, BL=-halfL
        let halfL = (dot(r1, u) + dot(r2, u) - dot(r0, u) - dot(r3, u)) / 4
        // タッチラインの半分：TL=-halfW, TR=-halfW, BR=+halfW, BL=+halfW（v は上→下）
        let halfW = (dot(r2, v) + dot(r3, v) - dot(r0, v) - dot(r1, v)) / 4
        
        guard halfL > 0, halfW > 0 else {
            return FieldCorners(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
        }
        
        // 補正済みコーナーを配置
        func corner(us: Double, vs: Double) -> Field.Coordinate {
            toC((
                x: cx + us * halfL * u.x + vs * halfW * v.x,
                y: cy + us * halfL * u.y + vs * halfW * v.y
            ))
        }
        
        // 4隅の言葉を保ったまま配置する。長い辺の判定による付け替えや、左右が逆のときの自動修正はしない
        // （ゴールラインの方が長い・左右が逆の登録は、登録画面で完了させない）
        return FieldCorners(
            topLeft:     corner(us: -1, vs: -1),
            topRight:    corner(us: +1, vs: -1),
            bottomRight: corner(us: +1, vs: +1),
            bottomLeft:  corner(us: -1, vs: +1)
        )
    }
    
    /// Firestoreとの変換用
    var dictionary: [String: Any] {
        [
            "id": id,
            "teamId": teamId,
            "name": name,
            "createdBy": createdBy,
            "createdAt": createdAt.timeIntervalSince1970, // TimeIntervalに変換
            "corners": [
                "topLeft": ["latitude": corners.topLeft.latitude, "longitude": corners.topLeft.longitude],
                "topRight": ["latitude": corners.topRight.latitude, "longitude": corners.topRight.longitude],
                "bottomRight": ["latitude": corners.bottomRight.latitude, "longitude": corners.bottomRight.longitude],
                "bottomLeft": ["latitude": corners.bottomLeft.latitude, "longitude": corners.bottomLeft.longitude]
            ],
            "dimensions": [
                "length": dimensions.length,
                "width": dimensions.width
            ]
        ]
    }
}
