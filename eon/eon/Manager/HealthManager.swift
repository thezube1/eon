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
    
    // Add properties for new metrics
    @Published var dateOfBirth: Date?
    @Published var biologicalSex: HKBiologicalSex = .notSet
    @Published var bloodType: HKBloodType = .notSet
    @Published var bodyMass: Double?
    @Published var height: Double?
    @Published var bmi: Double?
    
    // Add state to track background tasks
    private var backgroundTask: Task<Void, Never>?
    private var hasRunInitialAnalysis = false

    init() {
        // Load stored authorization status when the app launches
        self.isAuthorized = UserDefaults.standard.bool(forKey: "HealthKitAuthorized")
        
        // If already authorized, start background tasks
        if self.isAuthorized {
            print("HealthKit already authorized - Starting background tasks")
            fetchAllHealthData()
            startBackgroundTasks()
        }
    }
    
    // Add deinit to cancel background task
    deinit {
        backgroundTask?.cancel()
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        // Existing metrics
        if let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepType)
        }
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
        }
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        
        // Additional characteristics
        let characteristicTypes: [HKCharacteristicType] = [
            .characteristicType(forIdentifier: .dateOfBirth)!,
            .characteristicType(forIdentifier: .bloodType)!,
            .characteristicType(forIdentifier: .biologicalSex)!
        ]
        types.formUnion(characteristicTypes)
        
        // Body measurements
        if let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            types.insert(bodyMassType)
        }
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            types.insert(heightType)
        }
        if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            types.insert(bmiType)
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
                self.isAuthorized = success
                print("HealthKit Authorization Status Changed: \(success)")
                if success { 
                    self.fetchAllHealthData()
                    // Start background tasks after authorization
                    self.startBackgroundTasks()
                }
            }
            completion(success, error)
        }
    }

    func fetchAllHealthData() {
        fetchStepCount()
        fetchHeartRate()
        fetchSleepHours()
        fetchCharacteristics()
        fetchBodyMeasurements()
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

    func fetchSleepHours() {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        // Calculate the time window for last night's sleep
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        // Look back 12 hours from start of today to capture last night's sleep
        let lastNightStart = calendar.date(byAdding: .hour, value: -12, to: startOfToday)!
        
        print("Fetching sleep data from \(lastNightStart) to \(now)")
        
        let predicate = HKQuery.predicateForSamples(withStart: lastNightStart, end: now, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, error in
            if let error = error {
                print("Error fetching sleep data: \(error)")
                return
            }
            
            let totalSleep = results?
                .compactMap { $0 as? HKCategorySample }
                .filter { sample in
                    // Include all sleep stages that represent actual sleep
                    let sleepStages: Set<Int> = [
                        HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                        HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue
                    ]
                    return sleepStages.contains(sample.value)
                }
                .reduce(0.0) { acc, sample in
                    return acc + sample.endDate.timeIntervalSince(sample.startDate)
                } ?? 0
            
            DispatchQueue.main.async {
                self.sleepHours = totalSleep / 3600 // convert seconds to hours
                print("Updated sleep hours: \(self.sleepHours)")
            }
        }
        
        healthStore.execute(query)
    }
        
    // Add this function to your HealthManager class:
    func syncWithServer() async {
       do {
           print("Starting sync with deviceId: \(deviceId)")
           
           // Get sync status first
           let syncStatus = try await NetworkManager.shared.getSyncStatus(deviceId: deviceId)
           print("Retrieved sync status:")
           print("  Heart Rate Last Sync: \(syncStatus.syncStatus.heartRate ?? "never")")
           print("  Steps Last Sync: \(syncStatus.syncStatus.steps ?? "never")")
           print("  Sleep Last Sync: \(syncStatus.syncStatus.sleep ?? "never")")
           print("  Overall Last Sync: \(syncStatus.lastSync ?? "never")")
           
           var healthData: [String: [[String: Any]]] = [:]
           
           // For each metric, fetch data since its last sync time
           let formatter = ISO8601DateFormatter()
           
           // Heart Rate
           if let lastHeartRateSync = syncStatus.syncStatus.heartRate.flatMap({ formatter.date(from: $0) }) {
               if let heartRateData = await fetchHeartRateDataSince(lastHeartRateSync) {
                   healthData["heart_rate"] = heartRateData
               }
           } else {
               // If never synced, get last 24 hours
               let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
               if let heartRateData = await fetchHeartRateDataSince(oneDayAgo) {
                   healthData["heart_rate"] = heartRateData
               }
           }
           
           // Steps
           if let lastStepsSync = syncStatus.syncStatus.steps.flatMap({ formatter.date(from: $0) }) {
               if let stepData = await fetchStepDataSince(lastStepsSync) {
                   healthData["steps"] = stepData
               }
           } else {
               let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
               if let stepData = await fetchStepDataSince(oneDayAgo) {
                   healthData["steps"] = stepData
               }
           }
           
           // Sleep
           if let lastSleepSync = syncStatus.syncStatus.sleep.flatMap({ formatter.date(from: $0) }) {
               if let sleepData = await fetchSleepDataSince(lastSleepSync) {
                   healthData["sleep"] = sleepData
               }
           } else {
               let oneDayAgo = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
               if let sleepData = await fetchSleepDataSince(oneDayAgo) {
                   healthData["sleep"] = sleepData
               }
           }

           // Add characteristics data
           do {
               var characteristics: [String: Any] = [:]
               let dateFormatter = ISO8601DateFormatter()
               
               // Date of Birth - handle as optional
               do {
                   let dobComponents = try healthStore.dateOfBirthComponents()
                   if let date = Calendar.current.date(from: dobComponents) {
                       characteristics["date_of_birth"] = dateFormatter.string(from: date)
                   }
               } catch {
                   print("Error fetching date of birth: \(error)")
               }
               
               // Biological Sex - handle as optional
               do {
                   let biologicalSex = try healthStore.biologicalSex().biologicalSex
                   characteristics["biological_sex"] = biologicalSex.rawValue
               } catch {
                   print("Error fetching biological sex: \(error)")
               }
               
               // Blood Type - handle as optional
               do {
                   let bloodType = try healthStore.bloodType().bloodType
                   characteristics["blood_type"] = bloodType.rawValue
               } catch {
                   print("Error fetching blood type: \(error)")
               }
               
               // Only add characteristics if we have at least one value
               if !characteristics.isEmpty {
                   healthData["characteristics"] = [characteristics]
               }
           } catch {
               print("Error processing characteristics: \(error)")
           }
           
           // Add body measurements data
           var bodyMeasurements: [[String: Any]] = []
           let timestamp = ISO8601DateFormatter().string(from: Date())
           
           // Body Mass
           if let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              let latestWeight = try? await fetchLatestQuantitySample(for: bodyMassType) {
               let measurement: [String: Any] = [
                   "timestamp": timestamp,
                   "measurement_type": "weight",
                   "value": latestWeight.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo)),
                   "unit": "kg",
                   "source": latestWeight.sourceRevision.source.name
               ]
               bodyMeasurements.append(measurement)
           }
           
           // Height
           if let heightType = HKQuantityType.quantityType(forIdentifier: .height),
              let latestHeight = try? await fetchLatestQuantitySample(for: heightType) {
               let measurement: [String: Any] = [
                   "timestamp": timestamp,
                   "measurement_type": "height",
                   "value": latestHeight.quantity.doubleValue(for: HKUnit.meter()),
                   "unit": "m",
                   "source": latestHeight.sourceRevision.source.name
               ]
               bodyMeasurements.append(measurement)
           }
           
           // BMI
           if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex),
              let latestBMI = try? await fetchLatestQuantitySample(for: bmiType) {
               let measurement: [String: Any] = [
                   "timestamp": timestamp,
                   "measurement_type": "bmi",
                   "value": latestBMI.quantity.doubleValue(for: HKUnit.count()),
                   "unit": "count",
                   "source": latestBMI.sourceRevision.source.name
               ]
               bodyMeasurements.append(measurement)
           }
           
           if !bodyMeasurements.isEmpty {
               healthData["body_measurements"] = bodyMeasurements
           }
           
           // Only sync if we have data to sync
           if !healthData.isEmpty {
               try await NetworkManager.shared.syncHealthData(deviceId: deviceId, healthData: healthData)
               print("Sync completed successfully")
           } else {
               print("No new data to sync")
           }
           
           // Update last sync time
           DispatchQueue.main.async {
               self.lastSyncTime = Date()
           }
       } catch {
           print("Error syncing with server: \(error)")
       }
   }
   
   // Helper function to fetch latest quantity sample
   private func fetchLatestQuantitySample(for quantityType: HKQuantityType) async throws -> HKQuantitySample? {
       return try await withCheckedThrowingContinuation { continuation in
           let query = HKSampleQuery(
               sampleType: quantityType,
               predicate: nil,
               limit: 1,
               sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
           ) { _, samples, error in
               if let error = error {
                   continuation.resume(throwing: error)
                   return
               }
               continuation.resume(returning: samples?.first as? HKQuantitySample)
           }
           healthStore.execute(query)
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
                        
                        // Include all sleep stages that represent actual sleep
                        let sleepStages: Set<Int> = [
                            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                            HKCategoryValueSleepAnalysis.asleepREM.rawValue
                        ]
                        
                        let sleepValue = categorySample.value
                        let valueType = HKCategoryValueSleepAnalysis(rawValue: sleepValue)
                        
                        // Debug logging
                        print("Sleep sample - Start: \(categorySample.startDate)")
                        print("             End: \(categorySample.endDate)")
                        print("             Value: \(valueType?.rawValue ?? -1)")
                        print("             Duration: \(categorySample.endDate.timeIntervalSince(categorySample.startDate) / 3600) hours")
                        print("             Source: \(categorySample.sourceRevision.source.name)")
                        
                        if sleepStages.contains(categorySample.value) {
                            // Map the sleep stage to a string
                            let sleepStageStr = switch valueType {
                                case .asleepUnspecified: "unspecified"
                                case .asleepCore: "core"
                                case .asleepDeep: "deep"
                                case .asleepREM: "rem"
                                default: "unknown"
                            }
                            
                            return [
                                "start_time": ISO8601DateFormatter().string(from: categorySample.startDate),
                                "end_time": ISO8601DateFormatter().string(from: categorySample.endDate),
                                "sleep_stage": sleepStageStr,
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
    
    func dailySegments(completion: @escaping ([HalfHourSegment]) -> Void) {
        fetchTodaySleepSamples { sleepSamples in
            self.fetchTodayStepsByHalfHour { stepsDict in
                
                let calendar = Calendar.current
                guard let startOfDay = calendar.dateInterval(of: .day, for: Date())?.start else {
                    completion([])
                    return
                }
                
                var segments: [HalfHourSegment] = []
                for i in 0..<48 {
                    guard
                        let segmentStart = calendar.date(byAdding: .minute, value: i*30, to: startOfDay),
                        let segmentEnd = calendar.date(byAdding: .minute, value: (i+1)*30, to: startOfDay)
                    else {
                        continue
                    }
                    
                    // Determine the category for this block
                    let cat = self.categoryForTimeBlock(
                        start: segmentStart,
                        end: segmentEnd,
                        sleepSamples: sleepSamples,
                        stepsDict: stepsDict
                    )
                    segments.append(HalfHourSegment(startTime: segmentStart, category: cat))
                }
                
                completion(segments)
            }
        }
    }

    // Example using the helpers from above
    private func categoryForTimeBlock(start: Date,
                                      end: Date,
                                      sleepSamples: [HKCategorySample],
                                      stepsDict: [Date: Double]) -> ActivityCategory {
        if let majorStage = majoritySleepStage(start: start, end: end, samples: sleepSamples) {
            switch majorStage {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                return .deepSleep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                return .remSleep
            default:
                return .lightSleep
            }
        }
        
        let stepCountInBlock = stepsInBlock(start: start, end: end, stepsDict: stepsDict)
        switch stepCountInBlock {
        case _ where stepCountInBlock > 400: return .intense
        case 200...400: return .moderate
        case 50...199:  return .light
        case 1...49:    return .veryLight
        default:        return .inactive
        }
    }

    private func majoritySleepStage(start: Date,
                                    end: Date,
                                    samples: [HKCategorySample]) -> Int? {
        let blockDuration = end.timeIntervalSince(start)
        let halfBlock = blockDuration / 2.0
        
        let relevant = samples.filter { $0.startDate < end && $0.endDate > start }
        
        var totalByStage: [Int: TimeInterval] = [:]
        for sample in relevant {
            let overlapStart = max(sample.startDate, start)
            let overlapEnd = min(sample.endDate, end)
            let overlap = overlapEnd.timeIntervalSince(overlapStart)
            
            guard overlap > 0 else { continue }
            totalByStage[sample.value, default: 0] += overlap
        }
        
        // Debug prints
            print("Time Block: \(start) - \(end)")
            for (stageValue, totalTime) in totalByStage {
                print("  Stage \(stageValue) overlap: \(totalTime / 60) minutes")
            }
        
        guard let (stage, duration) = totalByStage.max(by: { a, b in a.value < b.value }) else {
            return nil
        }
        
        // Also print the chosen stage
            print("  => majority stage: \(stage) with \(duration / 60) minutes")
        
        return (duration >= halfBlock) ? stage : nil
    }

    private func stepsInBlock(start: Date,
                              end: Date,
                              stepsDict: [Date: Double]) -> Double {
        // If your dictionary keys match exactly with "start" times for each 30 min block:
        if let steps = stepsDict[start] {
            return steps
        }
        return 0
    }

    /// Fetch today's raw Sleep category samples
        func fetchTodaySleepSamples(completion: @escaping ([HKCategorySample]) -> Void) {
            guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
                print("Sleep type not available")
                completion([])
                return
            }
            
            let calendar = Calendar.current
            let now = Date()
            guard let startOfDay = calendar.dateInterval(of: .day, for: now)?.start else {
                completion([])
                return
            }
            
            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            
            let query = HKSampleQuery(sampleType: sleepType,
                                      predicate: predicate,
                                      limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [sortDescriptor]) { _, samples, error in
                if let error = error {
                    print("Error fetching today's sleep samples: \(error)")
                    completion([])
                    return
                }
                
                let sleepSamples = (samples as? [HKCategorySample]) ?? []
                completion(sleepSamples)
            }
            healthStore.execute(query)
        }

        /// Fetch step counts in 30-minute chunks for today
        func fetchTodayStepsByHalfHour(completion: @escaping ([Date: Double]) -> Void) {
            guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
                completion([:])
                return
            }
            
            let now = Date()
            guard let startOfDay = Calendar.current.dateInterval(of: .day, for: now)?.start else {
                completion([:])
                return
            }

            // We'll collect step totals in a dictionary keyed by each 30-min chunk start
            var interval = DateComponents()
            interval.minute = 30

            let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
            
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: startOfDay,
                intervalComponents: interval
            )
            
            query.initialResultsHandler = { _, results, error in
                guard let statsCollection = results, error == nil else {
                    completion([:])
                    return
                }
                
                var stepsDict: [Date: Double] = [:]
                statsCollection.enumerateStatistics(from: startOfDay, to: now) { stats, _ in
                    if let quantity = stats.sumQuantity() {
                        let stepCount = quantity.doubleValue(for: HKUnit.count())
                        // stats.startDate is the beginning of this 30-min bucket
                        stepsDict[stats.startDate] = stepCount
                    }
                }
                
                completion(stepsDict)
            }
            healthStore.execute(query)
        }

    // Update the checkAndSync method to simply call syncWithServer
    func checkAndSync() async {
        await syncWithServer()
    }

    // Add new function to manage background tasks
    private func startBackgroundTasks() {
        print("Starting background health tasks...")
        // Cancel any existing task
        backgroundTask?.cancel()
        
        // Create a new detached task that won't be cancelled by view transitions
        backgroundTask = Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            
            do {
                // First sync health data
                print("Starting initial health sync...")
                await self.syncWithServer()
                
                // Then run analysis and recommendations if needed
                if !self.hasRunInitialAnalysis {
                    print("Running initial analysis and recommendations...")
                    await self.runAnalysisAndRecommendations()
                    self.hasRunInitialAnalysis = true
                }
                
                print("Setting up periodic health sync...")
                // Set up periodic sync (every hour)
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 60 * 60 * 1_000_000_000) // 1 hour
                    if !Task.isCancelled {
                        print("Running periodic health sync...")
                        await self.syncWithServer()
                    }
                }
            } catch {
                print("Background task error: \(error)")
            }
        }
    }
    
    // Add function to run analysis and recommendations
    func runAnalysisAndRecommendations() async {
        do {
            print("Starting risk analysis calculation...")
            // First run risk analysis
            let riskAnalysisResponse = try await NetworkManager.shared.calculateRiskAnalysis(deviceId: deviceId)
            
            print("Risk analysis completed, checking predictions...")
            // If risk analysis succeeds and has predictions, get recommendations
            if riskAnalysisResponse.formatted_predictions.count > 0 {
                print("Generating recommendations based on risk analysis...")
                do {
                    _ = try await NetworkManager.shared.getRecommendations(deviceId: deviceId)
                    print("Recommendations generated successfully")
                } catch {
                    print("Error generating recommendations: \(error)")
                }
            } else {
                print("No predictions found in risk analysis response")
            }
        } catch {
            print("Error calculating risk analysis: \(error)")
            if let urlError = error as? URLError {
                print("URL Error details: \(urlError.localizedDescription)")
            }
        }
    }

    private func fetchCharacteristics() {
        do {
            // Date of Birth
            let dateOfBirth = try healthStore.dateOfBirthComponents()
            let calendar = Calendar.current
            if let date = calendar.date(from: dateOfBirth) {
                DispatchQueue.main.async {
                    self.dateOfBirth = date
                }
            }
            
            // Biological Sex
            let biologicalSex = try healthStore.biologicalSex().biologicalSex
            DispatchQueue.main.async {
                self.biologicalSex = biologicalSex
            }
            
            // Blood Type
            let bloodType = try healthStore.bloodType().bloodType
            DispatchQueue.main.async {
                self.bloodType = bloodType
            }
        } catch {
            print("Error fetching characteristics: \(error)")
        }
    }
    
    private func fetchBodyMeasurements() {
        // Fetch Body Mass
        if let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass) {
            let query = HKSampleQuery(sampleType: bodyMassType,
                                    predicate: nil,
                                    limit: 1,
                                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    DispatchQueue.main.async {
                        self?.bodyMass = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
                    }
                }
            }
            healthStore.execute(query)
        }
        
        // Fetch Height
        if let heightType = HKQuantityType.quantityType(forIdentifier: .height) {
            let query = HKSampleQuery(sampleType: heightType,
                                    predicate: nil,
                                    limit: 1,
                                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    DispatchQueue.main.async {
                        self?.height = sample.quantity.doubleValue(for: HKUnit.meter())
                    }
                }
            }
            healthStore.execute(query)
        }
        
        // Fetch BMI
        if let bmiType = HKQuantityType.quantityType(forIdentifier: .bodyMassIndex) {
            let query = HKSampleQuery(sampleType: bmiType,
                                    predicate: nil,
                                    limit: 1,
                                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { [weak self] _, samples, error in
                if let sample = samples?.first as? HKQuantitySample {
                    DispatchQueue.main.async {
                        self?.bmi = sample.quantity.doubleValue(for: HKUnit.count())
                    }
                }
            }
            healthStore.execute(query)
        }
    }
}

