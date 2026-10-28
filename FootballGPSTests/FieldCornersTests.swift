//
//  FieldCornersTests.swift
//  FootballGPSTests
//
//  フィールドの4隅を登録画面の言葉どおりに扱うことの確認（docs/フィールド表示向き仕様書.md）
//

import Testing
import CoreLocation
@testable import FootballGPS

struct FieldCornersTests {

    private let baseLat = 35.45
    private let baseLon = 139.60

    /// 基準点から東に east メートル、北に north メートルの座標
    private func coord(east: Double, north: Double) -> Field.Coordinate {
        let metersPerLat = 110540.0
        let metersPerLon = 111320.0 * cos(baseLat * .pi / 180.0)
        return Field.Coordinate(latitude: baseLat + north / metersPerLat, longitude: baseLon + east / metersPerLon)
    }

    /// 北が上の地図で、東西 eastWest m × 南北 northSouth m の長方形を見たまま（左上＝北西）登録する
    private func registerAsSeen(eastWest: Double, northSouth: Double) -> Field.FieldCorners {
        Field.correctToRectangle(
            topLeft: coord(east: 0, north: northSouth),
            topRight: coord(east: eastWest, north: northSouth),
            bottomRight: coord(east: eastWest, north: 0),
            bottomLeft: coord(east: 0, north: 0)
        )
    }

    @Test func 縦長のピッチを見たまま登録すると受け付ける() {
        let corners = registerAsSeen(eastWest: 68, northSouth: 105)
        #expect(!corners.isMirrored)
        #expect(!corners.isGoalLineLonger)
    }

    @Test func 横長のまま登録するとゴールラインの方が長いとして止まる() {
        let corners = registerAsSeen(eastWest: 105, northSouth: 68)
        #expect(!corners.isMirrored)
        #expect(corners.isGoalLineLonger)
    }

    @Test func 左上と右上を逆にタップすると左右が逆として止まる() {
        let corners = Field.correctToRectangle(
            topLeft: coord(east: 68, north: 105),
            topRight: coord(east: 0, north: 105),
            bottomRight: coord(east: 0, north: 0),
            bottomLeft: coord(east: 68, north: 0)
        )
        #expect(corners.isMirrored)
    }

    @Test func 正方形に近ければゴールラインの方が長くても止めない() {
        // ゴールライン 52m / タッチライン 50m = 1.04倍（1.1倍未満）
        let corners = registerAsSeen(eastWest: 52, northSouth: 50)
        #expect(!corners.isGoalLineLonger)
    }

    @Test func 補正しても4隅の言葉は入れ替わらない() {
        let corners = registerAsSeen(eastWest: 68, northSouth: 105)
        // 左上は北西のまま（付け替えで別の角にならない）
        let northWest = coord(east: 0, north: 105)
        #expect(abs(corners.topLeft.latitude - northWest.latitude) < 1e-6)
        #expect(abs(corners.topLeft.longitude - northWest.longitude) < 1e-6)
    }

    @Test func 寸法は縦がタッチライン横がゴールライン() {
        let corners = registerAsSeen(eastWest: 68, northSouth: 105)
        #expect(abs(corners.touchLineLength - 105) < 0.5)
        #expect(abs(corners.goalLineLength - 68) < 0.5)
    }

    @Test func 左上付近の点は画面の左上に描かれる座標になる() {
        let corners = registerAsSeen(eastWest: 68, northSouth: 105)
        let field = Field(
            teamId: "team",
            name: "テストフィールド",
            createdBy: "user",
            corners: corners,
            dimensions: Field.FieldDimensions(length: corners.touchLineLength, width: corners.goalLineLength)
        )
        let p = coord(east: 10, north: 95)
        guard let point = field.convertToFieldCoordinate(
            CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
        ) else {
            Issue.record("座標変換に失敗")
            return
        }
        // x: 左下→右下（画面の右）、y: 左下→左上（画面の上）
        #expect(abs(point.x - 10) < 0.5)
        #expect(abs(point.y - 95) < 0.5)
    }

    @Test func 回転した地図で登録しても言葉どおりの座標になる() {
        // 地図を回し、東西に延びるピッチを縦長に見て登録（左上＝北東、右上＝南東、右下＝南西、左下＝北西）
        let corners = Field.correctToRectangle(
            topLeft: coord(east: 105, north: 68),
            topRight: coord(east: 105, north: 0),
            bottomRight: coord(east: 0, north: 0),
            bottomLeft: coord(east: 0, north: 68)
        )
        #expect(!corners.isMirrored)
        #expect(!corners.isGoalLineLonger)

        let field = Field(
            teamId: "team",
            name: "テストフィールド",
            createdBy: "user",
            corners: corners,
            dimensions: Field.FieldDimensions(length: corners.touchLineLength, width: corners.goalLineLength)
        )
        // 北東寄り（左上寄り）の点
        let p = coord(east: 95, north: 60)
        guard let point = field.convertToFieldCoordinate(
            CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude)
        ) else {
            Issue.record("座標変換に失敗")
            return
        }
        #expect(point.x < 68 / 2)
        #expect(point.y > 105 / 2)
    }
}
