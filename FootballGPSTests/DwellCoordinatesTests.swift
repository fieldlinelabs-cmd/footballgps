//
//  DwellCoordinatesTests.swift
//  FootballGPSTests
//
//  長くいた場所の集計（機能仕様書 §9.2）の確認
//

import Testing
import Foundation
@testable import FootballGPS

@MainActor
struct DwellCoordinatesTests {

    // 南西 (35.6803, 139.7671) を原点に、1マス10%の割合で位置を指定する
    private let field = Field(
        teamId: "team",
        name: "テストフィールド",
        createdBy: "user",
        corners: Field.FieldCorners(
            topLeft: Field.Coordinate(latitude: 35.6813, longitude: 139.7671),
            topRight: Field.Coordinate(latitude: 35.6813, longitude: 139.7681),
            bottomRight: Field.Coordinate(latitude: 35.6803, longitude: 139.7681),
            bottomLeft: Field.Coordinate(latitude: 35.6803, longitude: 139.7671)
        )
    )
    private let orientation = CourtOrientation(isFlipped: false)

    private func point(at seconds: TimeInterval, fx: Double = 0.5, fy: Double) -> GPSPoint {
        GPSPoint(
            timestamp: Date(timeIntervalSince1970: seconds),
            latitude: 35.6803 + fy * 0.001,
            longitude: 139.7671 + fx * 0.001,
            speed: 0,
            altitude: 0,
            horizontalAccuracy: 5
        )
    }

    @Test func 止まっていた時間の分だけ数えられる() {
        // 守備サードに20秒止まってから、攻撃サードを1秒間隔で5点動いた
        let points = [point(at: 0, fy: 0.1)] + (0..<5).map { point(at: 20 + Double($0), fy: 0.9) }
        let coords = field.dwellCoordinates(of: points, orientation: orientation)
        #expect(coords.count == 25)
        #expect(coords.filter { $0.y < field.dimensions.length / 2 }.count == 20)

        let thirds = SessionDataManager.computeThirdRatios(
            gpsData: GPSData(sessionId: "s", points: points), field: field, orientation: orientation
        )
        #expect(thirds.defensive == 80)
        #expect(thirds.attacking == 20)
    }

    @Test func 上限を超えた間隔は上限で打ち切られる() {
        let points = [point(at: 0, fy: 0.5), point(at: 100, fy: 0.5)]
        let coords = field.dwellCoordinates(of: points, orientation: orientation)
        #expect(coords.count == Int(DwellConfig.maxGap) + 1)
    }

    @Test func 秒より細かい間隔でも時間の分だけ数えられる() {
        let points = (0..<20).map { point(at: Double($0) * 0.5, fy: 0.5) }
        // 最後の点は1秒分数えるので、記録は 0〜10.5 秒
        #expect(field.dwellCoordinates(of: points, orientation: orientation).count == 11)
    }

    @Test func フィールドのすぐ外は端に寄せて離れた位置は除く() throws {
        // フィールドの縦の長さの約2%外（約2m）と、30%外
        let points = [
            point(at: 0, fy: 1.02),
            point(at: 1, fy: 1.3),
            point(at: 2, fy: 1.3),
            point(at: 3, fy: -0.02),
        ]
        let coords = field.dwellCoordinates(of: points, orientation: orientation)
        #expect(coords.count == 2)
        #expect(try #require(coords.first).y == field.dimensions.length)
        #expect(try #require(coords.last).y == 0)
    }

    @Test func 間隔の途中で前後半の向きが変わる() {
        let points = [point(at: 0, fy: 0.2), point(at: 10, fy: 0.2)]
        let switched = CourtOrientation(isFlipped: false, switchDate: Date(timeIntervalSince1970: 4))
        let coords = field.dwellCoordinates(of: points, orientation: switched)
        #expect(coords.count == 11)
        #expect(coords.filter { $0.y < field.dimensions.length / 2 }.count == 4)
    }

    @Test func 空の記録と1点だけの記録で落ちない() {
        #expect(field.dwellCoordinates(of: [], orientation: orientation).isEmpty)
        #expect(field.dwellCoordinates(of: [point(at: 0, fy: 0.5)], orientation: orientation).count == 1)
    }
}
