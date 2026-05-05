//
//  MockDataGenerator.swift
//  FootballGPS
//
//  Created on 2026/03/01.
//

import Foundation
import CoreLocation

/// シミュレーター用のモックデータを生成
struct MockDataGenerator {
    
    /// リアルなサッカートレーニングのGPSデータを生成
    /// - Parameters:
    ///   - sessionId: セッションID
    ///   - duration: トレーニング時間(秒)
    ///   - field: フィールド情報
    /// - Returns: GPSデータ
    static func generateRealisticTrainingData(
        sessionId: String,
        duration: TimeInterval = 1800, // 30分
        field: Field
    ) -> GPSData {
        var points: [GPSPoint] = []
        let startDate = Date()
        
        // フィールドの中心座標を計算
        let centerLat = (field.corners.topLeft.latitude + field.corners.bottomRight.latitude) / 2
        let centerLon = (field.corners.topLeft.longitude + field.corners.bottomRight.longitude) / 2
        
        // フィールドのサイズ（緯度経度での幅）
        let latRange = abs(field.corners.bottomRight.latitude - field.corners.topLeft.latitude)
        let lonRange = abs(field.corners.topRight.longitude - field.corners.topLeft.longitude)
        
        // 2秒ごとにデータポイントを生成
        let interval: TimeInterval = 2.0
        let pointCount = Int(duration / interval)
        
        // シミュレーション用のパラメータ
        var currentLat = centerLat
        var currentLon = centerLon
        var currentDirection: Double = 0 // ラジアン
        var currentSpeed: Double = 0
        
        for i in 0..<pointCount {
            let timestamp = startDate.addingTimeInterval(Double(i) * interval)
            
            // ランダムな動きをシミュレート
            if i % 5 == 0 {
                // 5回に1回、方向と速度を変更
                currentDirection += Double.random(in: -0.5...0.5)
                
                // 速度をランダムに変更（0 - 7 m/s）
                let speedChange = Double.random(in: -2...3)
                currentSpeed = max(0, min(7, currentSpeed + speedChange))
            }
            
            // 現在の速度と方向で移動
            let distance = currentSpeed * interval // メートル
            
            // 緯度経度での移動量に変換（簡易計算）
            let metersPerDegreeLat = 111320.0
            let metersPerDegreeLon = metersPerDegreeLat * cos(currentLat * .pi / 180)
            
            let deltaLat = (cos(currentDirection) * distance) / metersPerDegreeLat
            let deltaLon = (sin(currentDirection) * distance) / metersPerDegreeLon
            
            currentLat += deltaLat
            currentLon += deltaLon
            
            // フィールド範囲内に収める
            let minLat = min(field.corners.topLeft.latitude, field.corners.bottomLeft.latitude)
            let maxLat = max(field.corners.topLeft.latitude, field.corners.bottomLeft.latitude)
            let minLon = min(field.corners.topLeft.longitude, field.corners.topRight.longitude)
            let maxLon = max(field.corners.topLeft.longitude, field.corners.topRight.longitude)
            
            // 範囲外に出たら跳ね返る
            if currentLat < minLat || currentLat > maxLat {
                currentDirection = -.pi - currentDirection
                currentLat = max(minLat, min(maxLat, currentLat))
            }
            if currentLon < minLon || currentLon > maxLon {
                currentDirection = -currentDirection
                currentLon = max(minLon, min(maxLon, currentLon))
            }
            
            // GPSポイントを追加
            let point = GPSPoint(
                timestamp: timestamp,
                latitude: currentLat,
                longitude: currentLon,
                speed: currentSpeed,
                altitude: 10 + Double.random(in: -0.5...0.5),
                horizontalAccuracy: Double.random(in: 5...15)
            )
            
            points.append(point)
        }
        
        return GPSData(sessionId: sessionId, points: points)
    }
    
    /// 簡易的なフィールドを生成（テスト用）
    static func generateTestField() -> Field {
        // 東京の適当な場所を基準
        let baseLat = 35.681236
        let baseLon = 139.767125
        
        // 標準的なサッカーフィールド: 105m × 68m
        let metersPerDegreeLat = 111320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(baseLat * .pi / 180)
        
        let latDelta = 105.0 / metersPerDegreeLat
        let lonDelta = 68.0 / metersPerDegreeLon
        
        let corners = Field.FieldCorners(
            topLeft: Field.Coordinate(
                latitude: baseLat + latDelta / 2,
                longitude: baseLon - lonDelta / 2
            ),
            topRight: Field.Coordinate(
                latitude: baseLat + latDelta / 2,
                longitude: baseLon + lonDelta / 2
            ),
            bottomRight: Field.Coordinate(
                latitude: baseLat - latDelta / 2,
                longitude: baseLon + lonDelta / 2
            ),
            bottomLeft: Field.Coordinate(
                latitude: baseLat - latDelta / 2,
                longitude: baseLon - lonDelta / 2
            )
        )
        
        return Field(
            teamId: "test_team",
            name: "テストフィールド",
            createdBy: "test_user",
            corners: corners,
            dimensions: .standard
        )
    }
    
    /// テスト用のトレーニングセッションを生成
    static func generateTestSession(duration: TimeInterval = 1800) -> (TrainingSession, GPSData, Field) {
        let field = generateTestField()
        let sessionId = UUID().uuidString
        
        let gpsData = generateRealisticTrainingData(
            sessionId: sessionId,
            duration: duration,
            field: field
        )
        
        // 統計を計算
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
        
        let avgSpeed = totalDistance / duration
        
        let session = TrainingSession(
            id: sessionId,
            userId: "test_user",
            name: "モックトレーニング - \(Int(duration / 60))分",
            date: Date(),
            duration: duration,
            totalDistance: totalDistance,
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed
        )
        
        return (session, gpsData, field)
    }
}

// MARK: - Preview用のモックデータ拡張

extension MockData {
    static func generateMockGPSData(sessionId: String) -> GPSData {
        let field = mockField
        return MockDataGenerator.generateRealisticTrainingData(
            sessionId: sessionId,
            duration: 1200, // 20分
            field: field
        )
    }
    
    static var mockField: Field {
        return MockDataGenerator.generateTestField()
    }
    
    static var mockSessions: [TrainingSession] {
        var sessions: [TrainingSession] = []
        
        for i in 0..<5 {
            let duration = TimeInterval([900, 1200, 1800, 2400, 3000][i])
            let (session, _, _) = MockDataGenerator.generateTestSession(duration: duration)
            var modifiedSession = session
            modifiedSession.date = Date().addingTimeInterval(-TimeInterval(i * 86400)) // i日前
            sessions.append(modifiedSession)
        }
        
        return sessions
    }
}

// MARK: - MockData構造体（既存のコードと統合）

struct MockData {
    // 既存のmockSessionsとmockFieldはextensionで定義
}
