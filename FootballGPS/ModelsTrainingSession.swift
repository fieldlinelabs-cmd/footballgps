//
//  TrainingSession.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation
import CoreLocation

/// トレーニングセッションのモデル
struct TrainingSession: Identifiable, Codable {
    let id: String
    let userId: String
    let teamId: String?
    var fieldId: String? // var に変更
    
    var name: String
    let date: Date
    var duration: TimeInterval // 秒
    
    // 公開設定
    var visibility: SessionVisibility
    
    // 統計データ
    var totalDistance: Double // メートル
    var maxSpeed: Double // m/s
    var avgSpeed: Double // m/s
    var sprintCount: Int?
    
    // コート入れ替え表示フラグ
    var isFlipped: Bool
    
    // GPSデータへのパス（Cloud Storageに保存）
    var gpsDataPath: String?
    
    enum SessionVisibility: String, Codable {
        case `public` = "public"
        case `private` = "private"
        case teamAdminOnly = "team_admin_only"
    }
    
    init(
        id: String = UUID().uuidString,
        userId: String,
        teamId: String? = nil,
        fieldId: String? = nil,
        name: String? = nil,
        date: Date = Date(),
        duration: TimeInterval = 0,
        visibility: SessionVisibility = .private,
        totalDistance: Double = 0,
        maxSpeed: Double = 0,
        avgSpeed: Double = 0,
        sprintCount: Int? = nil,
        isFlipped: Bool = false,
        gpsDataPath: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.teamId = teamId
        self.fieldId = fieldId
        self.name = name ?? Self.defaultName(for: date)
        self.date = date
        self.duration = duration
        self.visibility = visibility
        self.totalDistance = totalDistance
        self.maxSpeed = maxSpeed
        self.avgSpeed = avgSpeed
        self.sprintCount = sprintCount
        self.isFlipped = isFlipped
        self.gpsDataPath = gpsDataPath
    }
    
    /// デフォルトのセッション名（日時ベース）
    static func defaultName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
    
    /// Firestoreとの変換用
    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "userId": userId,
            "name": name,
            "date": date.timeIntervalSince1970, // TimeIntervalに変換
            "duration": duration,
            "visibility": visibility.rawValue,
            "totalDistance": totalDistance,
            "maxSpeed": maxSpeed,
            "avgSpeed": avgSpeed
        ]
        
        if let teamId = teamId { dict["teamId"] = teamId }
        if let fieldId = fieldId { dict["fieldId"] = fieldId }
        if let sprintCount = sprintCount { dict["sprintCount"] = sprintCount }
        if let gpsDataPath = gpsDataPath { dict["gpsDataPath"] = gpsDataPath }
        
        return dict
    }
}

/// GPS座標データポイント
struct GPSPoint: Codable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let speed: Double // m/s
    let altitude: Double // メートル
    let horizontalAccuracy: Double // 精度（メートル）
    
    init(timestamp: Date, latitude: Double, longitude: Double, speed: Double, altitude: Double, horizontalAccuracy: Double) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.altitude = altitude
        self.horizontalAccuracy = horizontalAccuracy
    }
    
    init(location: CLLocation) {
        self.timestamp = location.timestamp
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.speed = max(0, location.speed) // 負の値を除外
        self.altitude = location.altitude
        self.horizontalAccuracy = location.horizontalAccuracy
    }
}

/// GPSデータの配列（JSON保存用）
struct GPSData: Codable {
    let sessionId: String
    let points: [GPSPoint]
}
