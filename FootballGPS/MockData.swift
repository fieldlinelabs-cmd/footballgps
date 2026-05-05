//
//  MockData.swift
//  FootballGPS
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation
import CoreLocation

/// 開発用のモックデータ
struct MockData {
    
    // MARK: - Mock Sessions
    
    static let mockSessions: [TrainingSession] = [
        TrainingSession(
            id: "session1",
            userId: "user1",
            name: "午後練習",
            date: Date().addingTimeInterval(-86400), // 昨日
            duration: 5400, // 1.5時間
            totalDistance: 8500,
            maxSpeed: 7.2,
            avgSpeed: 1.57
        ),
        TrainingSession(
            id: "session2",
            userId: "user1",
            name: "2025/12/08 14:30",
            date: Date().addingTimeInterval(-172800), // 2日前
            duration: 7200, // 2時間
            totalDistance: 10200,
            maxSpeed: 8.1,
            avgSpeed: 1.42
        ),
        TrainingSession(
            id: "session3",
            userId: "user1",
            name: "朝練",
            date: Date().addingTimeInterval(-259200), // 3日前
            duration: 3600, // 1時間
            totalDistance: 6800,
            maxSpeed: 6.5,
            avgSpeed: 1.89
        )
    ]
    
    // MARK: - Mock GPS Data
    
    /// フィールド上を動き回るモックGPSデータを生成
    static func generateMockGPSData(sessionId: String, pointCount: Int = 200) -> GPSData {
        var points: [GPSPoint] = []
        
        // 基準点（フィールドの中心付近）
        let centerLat = 35.6812
        let centerLon = 139.7671
        
        let startDate = Date().addingTimeInterval(-3600) // 1時間前
        
        // ランダムウォーク + サッカーらしい動きのパターン
        var currentLat = centerLat
        var currentLon = centerLon
        
        for i in 0..<pointCount {
            // 時間経過
            let timestamp = startDate.addingTimeInterval(Double(i) * 3)
            
            // ランダムな移動（小さな範囲で動く）
            let deltaLat = Double.random(in: -0.0005...0.0005)
            let deltaLon = Double.random(in: -0.0005...0.0005)
            
            currentLat += deltaLat
            currentLon += deltaLon
            
            // フィールドの範囲内に制限（約100m × 70m）
            let latRange = 0.0009 // 約100m
            let lonRange = 0.0006 // 約70m
            currentLat = min(max(currentLat, centerLat - latRange/2), centerLat + latRange/2)
            currentLon = min(max(currentLon, centerLon - lonRange/2), centerLon + lonRange/2)
            
            // 速度（0-8 m/s、時々ダッシュ）
            let isDash = Double.random(in: 0...1) < 0.1 // 10%の確率でダッシュ
            let speed = isDash ? Double.random(in: 5...8) : Double.random(in: 0...3)
            
            let point = GPSPoint(
                timestamp: timestamp,
                latitude: currentLat,
                longitude: currentLon,
                speed: speed,
                altitude: 10.0,
                horizontalAccuracy: 5.0
            )
            
            points.append(point)
        }
        
        return GPSData(sessionId: sessionId, points: points)
    }
    
    // MARK: - Mock Field
    
    static let mockField = Field(
        id: "field1",
        teamId: "team1",
        name: "〇〇グラウンド",
        createdBy: "user1",
        corners: Field.FieldCorners(
            topLeft: Field.Coordinate(latitude: 35.6816, longitude: 139.7665),
            topRight: Field.Coordinate(latitude: 35.6816, longitude: 139.7677),
            bottomRight: Field.Coordinate(latitude: 35.6808, longitude: 139.7677),
            bottomLeft: Field.Coordinate(latitude: 35.6808, longitude: 139.7665)
        ),
        dimensions: Field.FieldDimensions(length: 105, width: 68)
    )
    
    // MARK: - Mock Team
    
    static let mockTeam = Team(
        id: "team1",
        name: "サンプルFC",
        inviteCode: "ABC123",
        createdBy: "user1",
        adminUserIds: ["user1"],
        memberUserIds: ["user2", "user3"]
    )
    
    // MARK: - Mock User
    
    static let mockUser = UserProfile(
        id: "user1",
        displayName: "山田太郎",
        email: "test@example.com",
        teamIds: ["team1"]
    )
}
