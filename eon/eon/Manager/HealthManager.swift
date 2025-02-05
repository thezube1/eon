//
//  HealthManager.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import Foundation
import HealthKit
import UIKit

class HealthManager: ObservableObject {
    let healthStore = HKHealthStore()
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    @Published var lastSyncTime: Date?
    
    @Published var isAuthorized: Bool {
        didSet {
            UserDefaults.standard.set(isAuthorized, forKey: "HealthKitAuthorized")
        }
    }
    
    @Published var stepCount: Double = 0.0
    @Published var sleepHours: Double = 0.0
    @Published var heartRate: Double = 0.0

    init() {
        // Load stored authorization status when the app launches
        self.isAuthorized = UserDefaults.standard.bool(forKey: "HealthKitAuthorized")
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepType)
        }
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
        }
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        return types
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
            completion(false, nil)
            return
        }
        
        healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success // ✅ This now persists across app launches
                print("HealthKit Authorization Status Changed: \(success)")
                if success { self.fetchAllHealthData() }
            }
            completion(success, error)
        }
    }

    private func fetchAllHealthData() {
        fetchStepCount()
        fetchHeartRate()
        fetchSleepHours()
    }

    private func fetchStepCount() {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let sum = result?.sumQuantity() else { return }
            DispatchQueue.main.async {
                self.stepCount = sum.doubleValue(for: HKUnit.count())
            }
        }
        healthStore.execute(query)
    }

    private func fetchHeartRate() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: heartRateType, quantitySamplePredicate: predicate, options: .discreteAverage) { _, result, _ in
            guard let avg = result?.averageQuantity() else { return }
            DispatchQueue.main.async {
                self.heartRate = avg.doubleValue(for: HKUnit(from: "count/min"))
            }
        }
        healthStore.execute(query)
    }

    private func fetchSleepHours() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, _ in
            let totalSleep = results?
                .compactMap { $0 as? HKCategorySample }
                .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue }
                .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } ?? 0
            
            DispatchQueue.main.async {
                self.sleepHours = totalSleep / 3600 // convert seconds to hours
            }
        }
        healthStore.execute(query)
    }
    
    // Add this function to your HealthManager class:
    func syncWithServer() async {
       do {
           print("Starting sync with deviceId: \(deviceId)")
           
           // First try to sync health data to create the device if it doesn't exist
           var initialHealthData: [String: [[String: Any]]] = [:]
           
           // Get initial data from the last 24 hours
           let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
           
           if let heartRateData = await fetchHeartRateDataSince(oneDayAgo) {
               initialHealthData["heart_rate"] = heartRateData
           }
           if let stepData = await fetchStepDataSince(oneDayAgo) {
               initialHealthData["steps"] = stepData
           }
           if let sleepData = await fetchSleepDataSince(oneDayAgo) {
               initialHealthData["sleep"] = sleepData
           }
           
           // Initial sync to ensure device exists
           try await NetworkManager.shared.syncHealthData(deviceId: deviceId, healthData: initialHealthData)
           print("Initial sync completed successfully")
           
           // Now get the sync status
           let syncStatus = try await NetworkManager.shared.getSyncStatus(deviceId: deviceId)
           print("Retrieved sync status:")
           print("  Heart Rate Last Sync: \(syncStatus.syncStatus.heartRate ?? "never")")
           print("  Steps Last Sync: \(syncStatus.syncStatus.steps ?? "never")")
           print("  Sleep Last Sync: \(syncStatus.syncStatus.sleep ?? "never")")
           print("  Overall Last Sync: \(syncStatus.lastSync ?? "never")")

           // If we have a last sync time, get data since then
           if let lastSync = syncStatus.lastSync.flatMap({ ISO8601DateFormatter().date(from: $0) }) {
               var healthData: [String: [[String: Any]]] = [:]
               
               if let heartRateData = await fetchHeartRateDataSince(lastSync) {
                   healthData["heart_rate"] = heartRateData
               }
               if let stepData = await fetchStepDataSince(lastSync) {
                   healthData["steps"] = stepData
               }
               if let sleepData = await fetchSleepDataSince(lastSync) {
                   healthData["sleep"] = sleepData
               }
               
               if !healthData.isEmpty {
                   try await NetworkManager.shared.syncHealthData(deviceId: deviceId, healthData: healthData)
                   print("Incremental sync completed successfully")
               }
           }
           
           // Update last sync time
           DispatchQueue.main.async {
               self.lastSyncTime = Date()
           }
       } catch {
           print("Error syncing with server: \(error)")
       }
   }
   
   // Add these helper functions to fetch data since last sync:
   private func fetchHeartRateDataSince(_ date: Date?) async -> [[String: Any]]? {
       guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
       
       let predicate = date.map { HKQuery.predicateForSamples(withStart: $0, end: Date(), options: .strictStartDate) }
       
       return await withCheckedContinuation { continuation in
           let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
               guard let samples = samples as? [HKQuantitySample], error == nil else {
                   continuation.resume(returning: nil)
                   return
               }
               
               let heartRateData = samples.map { sample -> [String: Any] in
                   [
                       "timestamp": ISO8601DateFormatter().string(from: sample.startDate),
                       "bpm": sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                       "source": sample.sourceRevision.source.name
                   ]
               }
               
               continuation.resume(returning: heartRateData)
           }
           
           healthStore.execute(query)
       }
   }
   
   private func fetchStepDataSince(_ date: Date?) async -> [[String: Any]]? {
       guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
       
       let startDate = date ?? Calendar.current.date(byAdding: .day, value: -1, to: Date())!
       let predicate = HKQuery.predicateForSamples(withStart: startDate, end: Date(), options: .strictStartDate)
       
       return await withCheckedContinuation { continuation in
           let query = HKStatisticsCollectionQuery(
               quantityType: stepType,
               quantitySamplePredicate: predicate,
               options: .cumulativeSum,
               anchorDate: Calendar.current.startOfDay(for: startDate),
               intervalComponents: DateComponents(day: 1)
           )
           
           query.initialResultsHandler = { _, results, error in
               guard let results = results, error == nil else {
                   continuation.resume(returning: nil)
                   return
               }
               
               var stepData: [[String: Any]] = []
               results.enumerateStatistics(from: startDate, to: Date()) { statistics, _ in
                   if let sum = statistics.sumQuantity() {
                       // Convert step count to integer
                       let stepCount = Int(sum.doubleValue(for: HKUnit.count()))
                       print("Processing step count for \(statistics.startDate): \(stepCount)")
                       
                       stepData.append([
                           "date": ISO8601DateFormatter().string(from: statistics.startDate),
                           "step_count": stepCount,
                           "source": "HealthKit"
                       ])
                   }
               }
               
               continuation.resume(returning: stepData)
           }
           
           healthStore.execute(query)
       }
   }
   
   private func fetchSleepDataSince(_ date: Date?) async -> [[String: Any]]? {
       guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
           print("Sleep type not available")
           return nil
       }
       
       // Look back 7 days if no date provided
       let startDate = date ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!
       let endDate = Date()
       print("\nFetching sleep data from \(startDate) to \(endDate)")
       
       let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
       let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
       
       return await withCheckedContinuation { continuation in
           let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, error in
               if let error = error {
                   print("Error fetching sleep data: \(error)")
                   continuation.resume(returning: nil ?? [])
                   return
               }
               
               print("Raw sleep samples count: \(samples?.count ?? 0)")
               
               let sleepData = samples?
                   .compactMap { sample -> [String: Any]? in
                       guard let categorySample = sample as? HKCategorySample else {
                           print("Sample is not a category sample")
                           return nil
                       }
                       
                       func sleepStageDescription(for value: HKCategoryValueSleepAnalysis?) -> String {
                           guard let value = value else { return "unknown" }
                           switch value {
                           case .inBed: return "In Bed"
                           case .asleepUnspecified: return "Asleep (Unspecified)"
                           case .awake: return "Awake"
                           case .asleepCore: return "Asleep (Core)"
                           case .asleepDeep: return "Asleep (Deep)"
                           case .asleepREM: return "Asleep (REM)"
                           @unknown default: return "Unknown Sleep Stage"
                           }
                       }
                       
                       let sleepValue = categorySample.value
                       let valueType = HKCategoryValueSleepAnalysis(rawValue: sleepValue)
                       print("Sleep sample - Start: \(categorySample.startDate)")
                       print("             End: \(categorySample.endDate)")
                       print("             Value: \(sleepStageDescription(for: valueType))")
                       print("             Duration: \(categorySample.endDate.timeIntervalSince(categorySample.startDate) / 3600) hours")
                       print("             Source: \(categorySample.sourceRevision.source.name)")
                       
                       if categorySample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue {
                           return [
                               "start_time": ISO8601DateFormatter().string(from: categorySample.startDate),
                               "end_time": ISO8601DateFormatter().string(from: categorySample.endDate),
                               "sleep_stage": "asleep",
                               "source": categorySample.sourceRevision.source.name
                           ]
                       }
                       return nil
                   }
               
               if let sleepData = sleepData {
                   print("\nProcessed sleep records: \(sleepData.count)")
                   for (index, record) in sleepData.enumerated() {
                       print("Record \(index + 1):")
                       print("  Start: \(record["start_time"] as? String ?? "unknown")")
                       print("  End: \(record["end_time"] as? String ?? "unknown")")
                       print("  Stage: \(record["sleep_stage"] as? String ?? "unknown")")
                       print("  Source: \(record["source"] as? String ?? "unknown")")
                   }
               }
               
               continuation.resume(returning: sleepData)
           }
           
           healthStore.execute(query)
       }
   }

}
