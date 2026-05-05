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
    
    @Published var heartRate: Double = 0 // BPM（後で実装）
    
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
            avgSpeed: avgSpeed
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
        locations.removeAll()
        gpsPoints.removeAll()
        startDate = nil
        totalPausedDuration = 0
        pauseStartDate = nil
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
        // データ収集時の処理（必要に応じて実装）
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
            
            // 精度が低すぎる場合は無視
            guard location.horizontalAccuracy < 50 else { return }
            
            self.locations.append(location)
            
            // GPSポイントとして保存
            let gpsPoint = GPSPoint(location: location)
            self.gpsPoints.append(gpsPoint)
            
            // 距離を計算
            if self.locations.count >= 2 {
                let previousLocation = self.locations[self.locations.count - 2]
                let distanceIncrement = location.distance(from: previousLocation)
                self.distance += distanceIncrement
            }
            
            // 速度を更新
            if location.speed >= 0 {
                self.currentSpeed = location.speed
                if location.speed > self.maxSpeed {
                    self.maxSpeed = location.speed
                }
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
        
        // 距離を計算
        if locations.count >= 2 {
            let previousLocation = locations[locations.count - 2]
            let distanceIncrement = location.distance(from: previousLocation)
            self.distance += distanceIncrement
        }
        
        // 速度を更新
        currentSpeed = simulatedSpeed
        if simulatedSpeed > maxSpeed {
            maxSpeed = simulatedSpeed
        }
        
        print("🧪 GPS生成: 緯度 \(String(format: "%.6f", simulatedLocation.lat)), 経度 \(String(format: "%.6f", simulatedLocation.lon)), 速度 \(String(format: "%.1f", simulatedSpeed))m/s, 総距離 \(String(format: "%.0f", distance))m")
    }
}
#endif

