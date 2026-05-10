//
//  WorkoutManager.swift
//  FootballGPS Watch App
//
//  Created by 木下美樹 on 2025/12/10.
//

import Foundation
import HealthKit
import CoreLocation
import Combine
import WatchConnectivity
import WatchKit

/// Apple Watchでワークアウト（GPS記録）を管理するクラス
@MainActor
class WorkoutManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isRunning = false
    @Published var isPaused = false
    
    @Published var elapsedTime: TimeInterval = 0
    @Published var distance: Double = 0 // メートル
    @Published var currentSpeed: Double = 0 // m/s
    @Published var maxSpeed: Double = 0 // m/s
    
    @Published var heartRate: Double = 0 // BPM
    @Published var activeCalories: Double = 0 // kcal
    @Published var sprintCount: Int = 0
    @Published var zoneDistances: [Double] = [0, 0, 0, 0, 0] // Zone1-5 (m)

    @Published var startPointConfirmed: Bool = false

    // GPS記録データ（デバッグ用に公開）
    @Published var gpsPoints: [GPSPoint] = []
    
    // MARK: - Private Properties
    
    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    
    private let locationManager = CLLocationManager()
    private var locations: [CLLocation] = []
    
    private var startDate: Date?
    private var timer: Timer?
    private var totalPausedDuration: TimeInterval = 0
    private var pauseStartDate: Date?

    // スプリント検出用
    private var isInSprintCandidate = false
    private var sprintCandidateStartTime: Date?
    private var isInSprint = false
    private var lastSprintEndTime: Date?

    // GPS 安定待ちフィルタ用（破棄した点も含む直前の位置）
    private var previousLocation: CLLocation?
    
    // シミュレーター用のGPSシミュレーション
    #if targetEnvironment(simulator)
    private var gpsSimulationTimer: Timer?
    private var simulatedLocation: (lat: Double, lon: Double) = (35.681236, 139.767125) // 東京の座標
    private var simulatedDirection: Double = 0
    private var simulatedSpeed: Double = 0
    #endif
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // WatchConnectivityサービスを初期化
        _ = WatchConnectivityService.shared
        print("🔄 WorkoutManager初期化: WatchConnectivity準備完了")
        
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 2 // 2メートルごとに更新
        locationManager.activityType = .fitness
        
        // バックグラウンド位置情報更新（実機のみ有効化）
        // Info.plist に UIBackgroundModes (location, workout-processing) が必要
        #if !targetEnvironment(simulator)
        locationManager.allowsBackgroundLocationUpdates = true
        #endif
    }
    
    // MARK: - Permissions
    
    /// HealthKitとLocationの許可を要求
    func requestAuthorization() async throws {
        // HealthKit許可
        let typesToShare: Set = [
            HKQuantityType.workoutType()
        ]
        
        let typesToRead: Set = [
            HKQuantityType.workoutType(), // ⚠️ workoutRoute を読み取る際は workout も必要
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
            HKSeriesType.workoutRoute()
        ]
        
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        
        // Location許可
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Workout Control
    
    /// ワークアウトを開始
    func startWorkout() async throws {
        #if !targetEnvironment(simulator)
        // 実機のみ: HealthKit Workout Session を作成
        print("🏃 実機モード: HealthKit Workout Session を作成します")
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .soccer
        configuration.locationType = .outdoor
        
        session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        builder = session?.associatedWorkoutBuilder()
        
        session?.delegate = self
        builder?.delegate = self
        
        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )
        
        let startDate = Date()
        self.startDate = startDate
        
        session?.startActivity(with: startDate)
        try await builder?.beginCollection(at: startDate)
        #else
        // シミュレータ: HealthKit を使わず、単純に開始
        print("⚠️ シミュレータモード: HealthKit Workout をスキップします")
        self.startDate = Date()
        #endif
        
        // GPS記録開始
        locationManager.startUpdatingLocation()
        
        // シミュレーター用: 疑似GPS生成を開始
        #if targetEnvironment(simulator)
        startGPSSimulation()
        #endif
        
        // タイマー開始
        startTimer()
        
        isRunning = true
        isPaused = false
        
        print("✅ ワークアウト開始")
    }
    
    /// ワークアウトを一時停止
    func pauseWorkout() {
        #if !targetEnvironment(simulator)
        session?.pause()
        #else
        stopGPSSimulation()
        #endif
        locationManager.stopUpdatingLocation()
        stopTimer()
        pauseStartDate = Date()
        isPaused = true
        print("⏸️ ワークアウト一時停止")
    }
    
    /// ワークアウトを再開
    func resumeWorkout() {
        #if !targetEnvironment(simulator)
        session?.resume()
        #else
        startGPSSimulation()
        #endif
        if let pauseStart = pauseStartDate {
            totalPausedDuration += Date().timeIntervalSince(pauseStart)
            pauseStartDate = nil
        }
        locationManager.startUpdatingLocation()
        startTimer()
        isPaused = false
        print("▶️ ワークアウト再開")
    }
    
    /// ワークアウトを終了
    func endWorkout() async throws {
        #if !targetEnvironment(simulator)
        // 実機のみ: HealthKit Session を終了
        session?.end()
        try await builder?.endCollection(at: Date())
        #else
        print("⚠️ シミュレータモード: HealthKit Workout 終了をスキップします")
        stopGPSSimulation()
        #endif
        
        locationManager.stopUpdatingLocation()
        stopTimer()
        
        // ⚠️ isRunning は サマリー画面を閉じる時に false にする
        // isRunning = false
        isPaused = false
        
        print("🛑 ワークアウト終了")
        print("📊 総距離: \(distance)m, 最高速度: \(maxSpeed)m/s")
        print("📍 記録したポイント数: \(gpsPoints.count)")
        
        // iPhoneへデータを送信
        sendDataToiPhone()
    }
    
    /// iPhoneへセッションデータを送信
    private func sendDataToiPhone() {
        guard let sessionData = getSessionData() else {
            print("⚠️ セッションデータがありません")
            return
        }
        
        print("📤 iPhoneへデータ送信開始...")
        
        #if targetEnvironment(simulator)
        // シミュレーター: WatchConnectivityが動作しないため、UserDefaultsに保存
        print("🧪 シミュレーターモード: UserDefaultsに直接保存します")
        saveToSharedUserDefaults(session: sessionData.session, gpsData: sessionData.gpsData)
        print("✅ データ保存完了 - iPhoneアプリで確認してください")
        #else
        // 実機: WatchConnectivityを使用
        let connectivityService = WatchConnectivityService.shared
        
        // WatchConnectivityの初期化を待つ(最大3秒)
        var retryCount = 0
        let maxRetries = 6
        
        func attemptSend() {
            if WCSession.default.activationState == .activated {
                print("✅ WatchConnectivity準備完了 - データ送信")
                connectivityService.sendSession(
                    sessionData.session,
                    gpsData: sessionData.gpsData
                )
            } else if retryCount < maxRetries {
                retryCount += 1
                print("⏳ WatchConnectivity初期化待機中... (\(retryCount)/\(maxRetries))")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    attemptSend()
                }
            } else {
                print("❌ WatchConnectivity初期化タイムアウト - データ送信失敗")
            }
        }
        
        // 初回実行
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            attemptSend()
        }
        #endif
    }
    
    #if targetEnvironment(simulator)
    /// シミュレーター用: UserDefaultsに直接保存
    private func saveToSharedUserDefaults(session: TrainingSession, gpsData: GPSData) {
        // App Groupを使用して、WatchとiPhoneでデータを共有
        // Note: 実際にはApp Groupの設定が必要ですが、シミュレーターではUserDefaults.standardでも動作します
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        // セッションデータを保存
        if let sessionData = try? encoder.encode(session) {
            UserDefaults.standard.set(sessionData, forKey: "pendingSession_\(session.id)")
        }
        
        // GPSデータを保存
        if let gpsDataEncoded = try? encoder.encode(gpsData) {
            UserDefaults.standard.set(gpsDataEncoded, forKey: "pendingGPS_\(session.id)")
        }
        
        // 保留中のセッションIDリストに追加
        var pendingIds = UserDefaults.standard.stringArray(forKey: "pendingSessionIds") ?? []
        if !pendingIds.contains(session.id) {
            pendingIds.append(session.id)
            UserDefaults.standard.set(pendingIds, forKey: "pendingSessionIds")
        }
        
        UserDefaults.standard.synchronize()
        
        print("💾 データをUserDefaultsに保存:")
        print("   - セッションID: \(session.id)")
        print("   - GPSポイント数: \(gpsData.points.count)")
    }
    #endif
    
    /// セッションデータを取得（保存用）
    func getSessionData() -> (session: TrainingSession, gpsData: GPSData)? {
        guard let startDate = startDate else { return nil }
        
        // TODO: 実際のuserIdを取得（Firebase Authから）
        let userId = "temp_user_id"
        
        let avgSpeed = distance > 0 ? distance / elapsedTime : 0
        
        let session = TrainingSession(
            userId: userId,
            date: startDate,
            duration: elapsedTime,
            totalDistance: distance,
            maxSpeed: maxSpeed,
            avgSpeed: avgSpeed,
            sprintCount: sprintCount
        )
        
        let gpsData = GPSData(
            sessionId: session.id,
            points: gpsPoints
        )
        
        return (session, gpsData)
    }
    
    /// データをリセット
    func reset() {
        elapsedTime = 0
        distance = 0
        currentSpeed = 0
        maxSpeed = 0
        heartRate = 0
        activeCalories = 0
        sprintCount = 0
        zoneDistances = [0, 0, 0, 0, 0]
        locations.removeAll()
        gpsPoints.removeAll()
        startDate = nil
        totalPausedDuration = 0
        pauseStartDate = nil
        isInSprintCandidate = false
        sprintCandidateStartTime = nil
        isInSprint = false
        lastSprintEndTime = nil
        previousLocation = nil
        startPointConfirmed = false
    }
    
    // MARK: - Timer
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        guard let start = startDate else { return }
        elapsedTime = Date().timeIntervalSince(start) - totalPausedDuration
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Speed Processing

    /// 速度ゾーン別距離加算とスプリント検出
    private func processSpeedUpdate(speed: Double, timestamp: Date, distanceIncrement: Double) {
        // 速度ゾーン別距離の加算
        let zoneIndex: Int
        switch speed {
        case ..<2.0:    zoneIndex = 0 // 静止/歩行
        case 2.0..<4.0: zoneIndex = 1 // ジョギング
        case 4.0..<5.5: zoneIndex = 2 // ランニング
        case 5.5..<7.0: zoneIndex = 3 // 高速ラン
        default:        zoneIndex = 4 // スプリント
        }
        zoneDistances[zoneIndex] += distanceIncrement

        // スプリント検出
        let sprintThreshold: Double = 5.5
        let sprintEndThreshold: Double = 4.5
        let minSprintDuration: TimeInterval = 2.0
        let minSprintInterval: TimeInterval = 5.0

        if isInSprint {
            if speed < sprintEndThreshold {
                isInSprint = false
                isInSprintCandidate = false
                sprintCount += 1
                lastSprintEndTime = timestamp
            }
        } else if isInSprintCandidate {
            if speed < sprintEndThreshold {
                isInSprintCandidate = false
                sprintCandidateStartTime = nil
            } else if let candidateStart = sprintCandidateStartTime,
                      timestamp.timeIntervalSince(candidateStart) >= minSprintDuration {
                isInSprint = true
            }
        } else {
            if speed >= sprintThreshold {
                let canStart = lastSprintEndTime == nil ||
                    timestamp.timeIntervalSince(lastSprintEndTime!) >= minSprintInterval
                if canStart {
                    isInSprintCandidate = true
                    sprintCandidateStartTime = timestamp
                }
            }
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        Task { @MainActor in
            switch toState {
            case .running:
                print("▶️ セッション実行中")
            case .paused:
                print("⏸️ セッション一時停止")
            case .ended:
                print("🛑 セッション終了")
            default:
                break
            }
        }
    }
    
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("❌ ワークアウトエラー: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            // Sendable な Double? として事前に取得してから Task に渡す
            if quantityType == HKQuantityType.quantityType(forIdentifier: .heartRate) {
                let bpm = workoutBuilder.statistics(for: quantityType)?.mostRecentQuantity()?
                    .doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                Task { @MainActor in
                    if let bpm { self.heartRate = bpm }
                }
            } else if quantityType == HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
                let kcal = workoutBuilder.statistics(for: quantityType)?.sumQuantity()?
                    .doubleValue(for: .kilocalorie())
                Task { @MainActor in
                    if let kcal { self.activeCalories = kcal }
                }
            }
        }
    }
    
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        // イベント収集時の処理
    }
}

// MARK: - CLLocationManagerDelegate

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        Task { @MainActor in
            guard let location = locations.last else { return }

            // GPS 安定待ちフィルタ: 2条件チェック
            // 条件1: 水平精度 < 20m（GPS が安定していることを確認）
            let isAccurate = location.horizontalAccuracy < 20.0
            // 条件2: 直前位置との推定速度 < 12 m/s（ジャンプでないことを確認）
            let isNotJump: Bool
            if let prev = self.previousLocation {
                let elapsed = location.timestamp.timeIntervalSince(prev.timestamp)
                let impliedSpeed = location.distance(from: prev) / max(elapsed, 0.1)
                isNotJump = impliedSpeed < 12.0
            } else {
                isNotJump = true  // 初回点はジャンプ判定をスキップ
            }
            // 破棄する点も含めて常に更新（次回のジャンプ判定基準として使用）
            self.previousLocation = location

            guard isAccurate && isNotJump else { return }

            // 初回点確定: Start地点確定フィードバック
            if self.gpsPoints.isEmpty {
                WKInterfaceDevice.current().play(.success)
                self.startPointConfirmed = true
            }

            // 直前の承認済み位置を取得してから追加
            let prevAcceptedLocation = self.locations.last
            self.locations.append(location)

            // GPSポイントとして保存
            let gpsPoint = GPSPoint(location: location)
            self.gpsPoints.append(gpsPoint)

            // 距離を計算 (GPS ドリフトフィルタ: 0.3 m/s 未満は加算しない)
            var distanceIncrement = 0.0
            if let prevLocation = prevAcceptedLocation {
                let d = location.distance(from: prevLocation)
                if location.speed >= 0.3 {
                    self.distance += d
                    distanceIncrement = d
                }
            }

            // 速度を更新
            if location.speed >= 0 {
                let speed = location.speed
                self.currentSpeed = speed
                if speed > self.maxSpeed { self.maxSpeed = speed }
                // 速度ゾーン・スプリント処理
                self.processSpeedUpdate(speed: speed, timestamp: location.timestamp, distanceIncrement: distanceIncrement)
            }

            print("📍 GPS更新: 速度 \(String(format: "%.1f", location.speed))m/s, 総距離 \(String(format: "%.0f", self.distance))m")
        }
    }
    
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        print("❌ 位置情報エラー: \(error.localizedDescription)")
    }
}

// MARK: - GPS Simulation for Simulator

#if targetEnvironment(simulator)
extension WorkoutManager {
    
    /// シミュレーター用のGPS位置情報生成を開始
    private func startGPSSimulation() {
        print("🧪 シミュレーターモード: GPS位置情報シミュレーション開始")
        
        // 初期位置をランダムに設定
        simulatedLocation = (35.681236 + Double.random(in: -0.001...0.001),
                            139.767125 + Double.random(in: -0.001...0.001))
        simulatedDirection = Double.random(in: 0...(2 * .pi))
        simulatedSpeed = 0
        
        // 2秒ごとにGPSポイントを生成
        gpsSimulationTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.generateSimulatedGPSPoint()
            }
        }
    }
    
    /// シミュレーター用のGPS位置情報生成を停止
    private func stopGPSSimulation() {
        print("🧪 シミュレーターモード: GPS位置情報シミュレーション停止")
        gpsSimulationTimer?.invalidate()
        gpsSimulationTimer = nil
    }
    
    /// シミュレートされたGPSポイントを生成
    private func generateSimulatedGPSPoint() {
        // 5回に1回、速度と方向を変更
        if Int.random(in: 0..<5) == 0 {
            simulatedDirection += Double.random(in: -0.5...0.5)
            
            // 速度をランダムに変更(0 - 7 m/s)
            let speedChange = Double.random(in: -2.0...3.0)
            simulatedSpeed = max(0, min(7, simulatedSpeed + speedChange))
        }
        
        // 現在の速度と方向で移動
        let distance = simulatedSpeed * 2.0 // 2秒間の移動距離
        
        // 緯度経度での移動量に変換
        let metersPerDegreeLat = 111320.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(simulatedLocation.lat * .pi / 180)
        
        let deltaLat = (cos(simulatedDirection) * distance) / metersPerDegreeLat
        let deltaLon = (sin(simulatedDirection) * distance) / metersPerDegreeLon
        
        simulatedLocation.lat += deltaLat
        simulatedLocation.lon += deltaLon
        
        // フィールド範囲内に収める(簡易的な境界チェック)
        let fieldRange = 0.0015 // 約150m
        let centerLat = 35.681236
        let centerLon = 139.767125
        
        if abs(simulatedLocation.lat - centerLat) > fieldRange {
            simulatedDirection = -.pi - simulatedDirection
            simulatedLocation.lat = centerLat + (simulatedLocation.lat > centerLat ? fieldRange : -fieldRange)
        }
        if abs(simulatedLocation.lon - centerLon) > fieldRange {
            simulatedDirection = -simulatedDirection
            simulatedLocation.lon = centerLon + (simulatedLocation.lon > centerLon ? fieldRange : -fieldRange)
        }
        
        // 疑似的なCLLocationを作成
        // Note: CLLocationのspeedは後から設定できないため、
        // GPSPointに直接速度を設定
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: simulatedLocation.lat, longitude: simulatedLocation.lon),
            altitude: 10,
            horizontalAccuracy: 10,
            verticalAccuracy: 5,
            timestamp: Date()
        )
        
        // GPSポイントとして保存(速度情報を含む)
        let gpsPoint = GPSPoint(
            timestamp: Date(),
            latitude: simulatedLocation.lat,
            longitude: simulatedLocation.lon,
            speed: simulatedSpeed,
            altitude: 10,
            horizontalAccuracy: 10
        )
        gpsPoints.append(gpsPoint)
        locations.append(location)
        
        // 距離を計算 (GPS ドリフトフィルタ: 0.3 m/s 未満は加算しない)
        var distanceIncrement = 0.0
        if locations.count >= 2 {
            let previousLocation = locations[locations.count - 2]
            let d = location.distance(from: previousLocation)
            if simulatedSpeed >= 0.3 {
                self.distance += d
                distanceIncrement = d
            }
        }

        // 速度を更新
        currentSpeed = simulatedSpeed
        if simulatedSpeed > maxSpeed { maxSpeed = simulatedSpeed }

        // 速度ゾーン・スプリント処理
        processSpeedUpdate(speed: simulatedSpeed, timestamp: Date(), distanceIncrement: distanceIncrement)

        print("🧪 GPS生成: 緯度 \(String(format: "%.6f", simulatedLocation.lat)), 経度 \(String(format: "%.6f", simulatedLocation.lon)), 速度 \(String(format: "%.1f", simulatedSpeed))m/s, 総距離 \(String(format: "%.0f", distance))m")
    }
}
#endif

