//
//  AdConfigurationTests.swift
//  FootballGPSTests
//
//  広告の設定（docs/広告仕様書.md §10.2・§10.3）の確認
//

import Testing
import StoreKit
@testable import FootballGPS

struct AdConfigurationTests {

    // MARK: - 本番とテストのどちらの広告を使うか（§10.2）

    @Test func debugBuildAlwaysUsesTestAds() {
        for environment in [nil, .appStore, .testFlight, .xcode, .unknown] as [DistributionEnvironment?] {
            #expect(AdConfiguration.adSource(isDebugBuild: true, environment: environment) == .test)
        }
    }

    @Test func releaseFromAppStoreUsesProductionAds() {
        #expect(AdConfiguration.adSource(isDebugBuild: false, environment: .appStore) == .production)
    }

    @Test func releaseOutsideAppStoreUsesTestAds() {
        #expect(AdConfiguration.adSource(isDebugBuild: false, environment: .testFlight) == .test)
        #expect(AdConfiguration.adSource(isDebugBuild: false, environment: .xcode) == .test)
        // 判定に失敗したら、本番の広告がテスターに出ないようテスト広告にする
        #expect(AdConfiguration.adSource(isDebugBuild: false, environment: .unknown) == .test)
    }

    @Test func releaseWaitsUntilEnvironmentIsResolved() {
        // 判定中にApp Store版へテスト広告を出さないよう、広告を読み込まない
        #expect(AdConfiguration.adSource(isDebugBuild: false, environment: nil) == .undetermined)
    }

    @Test func storeEnvironmentMapping() {
        #expect(AdConfiguration.distributionEnvironment(from: .production) == .appStore)
        #expect(AdConfiguration.distributionEnvironment(from: .sandbox) == .testFlight)
        #expect(AdConfiguration.distributionEnvironment(from: .xcode) == .xcode)
    }

    // MARK: - 子ども向けのタグ（§10.3）

    @Test func childDirectedOnlyWhenKnownUnder13() {
        #expect(AdConfiguration.isChildDirected(age: 12))
        #expect(AdConfiguration.isChildDirected(age: 0))
        #expect(!AdConfiguration.isChildDirected(age: 13))
        #expect(!AdConfiguration.isChildDirected(age: 30))
        // 生年月日が未入力なら付けない
        #expect(!AdConfiguration.isChildDirected(age: nil))
    }
}
