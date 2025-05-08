import Foundation
import HealthKit
import UIKit
import Combine

class OnboardingManager: ObservableObject {
    let healthStore = HKHealthStore()
    private let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    private let dateFormatter = ISO8601DateFormatter()
    
    @Published var isOnboarding = false
    @Published var onboardingProgress: Double = 0.0
    @Published var onboardingCompleted = false
    @Published var error: String? = nil
    
    // Date range for historical data (30 days)
    private var startDate: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    }
    private var endDate: Date {
        Date()
    }
    
    // Health data types we want to fetch during onboarding
    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        // Core metrics
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
    
    // Request HealthKit authorization
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            self.error = "HealthKit is not available on this device"
            return false
        }
        
        do {
            return try await withCheckedThrowingContinuation { continuation in
                healthStore.requestAuthorization(toShare: nil, read: readTypes) { success, error in
                    if let error = error {
                        print("HealthKit authorization error: \(error)")
                        continuation.resume(returning: false)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
        } catch {
            print("Error during HealthKit authorization: \(error)")
            return false
        }
    }
    
    // Main function to start the onboarding process
    func startOnboarding() async {
        DispatchQueue.main.async {
            self.isOnboarding = true
            self.onboardingProgress = 0.0
            self.error = nil
        }
        
        print("Starting health data onboarding...")
        
        // Step 1: Request HealthKit authorization
        let authorized = await requestAuthorization()
        if !authorized {
            DispatchQueue.main.async {
                self.isOnboarding = false
                self.error = "Failed to get HealthKit authorization"
            }
            return
        }
        
        DispatchQueue.main.async {
            self.onboardingProgress = 0.1
        }
        
        // Step 2: Fetch historical health data
        do {
            // Fetch all health data for the past 30 days
            let healthData = await fetchHistoricalHealthData()
            
            DispatchQueue.main.async {
                self.onboardingProgress = 0.6
            }
            
            // Step 3: Send data to server
            try await NetworkManager.shared.onboardHealthData(deviceId: deviceId, healthData: healthData)
            
            DispatchQueue.main.async {
                self.onboardingProgress = 0.8
            }
            
            // Step 4: Trigger risk analysis and recommendations
            await generateAnalysisAndRecommendations()
            
            DispatchQueue.main.async {
                self.onboardingProgress = 1.0
                self.onboardingCompleted = true
                self.isOnboarding = false
            }
            
            print("Onboarding completed successfully")
        } catch {
            print("Onboarding error: \(error)")
            DispatchQueue.main.async {
                self.error = "Failed to complete onboarding: \(error.localizedDescription)"
                self.isOnboarding = false
            }
        }
    }
    
    // Fetch historical health data (30 days)
    private func fetchHistoricalHealthData() async -> [String: Any] {
        var healthData: [String: Any] = [:]
        
        // Heart Rate
        if let heartRateData = await fetchHeartRateData() {
            healthData["heart_rate"] = heartRateData
            DispatchQueue.main.async {
                self.onboardingProgress += 0.1
            }
        }
        
        // Steps
        if let stepData = await fetchStepData() {
            healthData["steps"] = stepData
            DispatchQueue.main.async {
                self.onboardingProgress += 0.1
            }
        }
        
        // Sleep
        if let sleepData = await fetchSleepData() {
            healthData["sleep"] = sleepData
            DispatchQueue.main.async {
                self.onboardingProgress += 0.1
            }
        }
        
        // Characteristics
        let characteristics = await fetchCharacteristics()
        if !characteristics.isEmpty {
            healthData["characteristics"] = [characteristics]
            DispatchQueue.main.async {
                self.onboardingProgress += 0.1
            }
        }
        
        // Body measurements
        let bodyMeasurements = await fetchBodyMeasurements()
        if !bodyMeasurements.isEmpty {
            healthData["body_measurements"] = bodyMeasurements
            DispatchQueue.main.async {
                self.onboardingProgress += 0.1
            }
        }
        
        return healthData
    }
    
    // Fetch 30 days of heart rate data
    private func fetchHeartRateData() async -> [[String: Any]]? {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heartRateType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                guard let samples = samples as? [HKQuantitySample], error == nil else {
                    print("Error fetching heart rate data: \(error?.localizedDescription ?? "unknown error")")
                    continuation.resume(returning: nil)
                    return
                }
                
                let heartRateData = samples.map { sample -> [String: Any] in
                    [
                        "timestamp": self.dateFormatter.string(from: sample.startDate),
                        "bpm": sample.quantity.doubleValue(for: HKUnit(from: "count/min")),
                        "source": sample.sourceRevision.source.name,
                        "context": "onboarding" // Mark this as onboarding data
                    ]
                }
                
                print("Fetched \(heartRateData.count) heart rate records")
                continuation.resume(returning: heartRateData)
            }
            
            healthStore.execute(query)
        }
    }
    
    // Fetch 30 days of step data
    private func fetchStepData() async -> [[String: Any]]? {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return nil }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        
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
                    print("Error fetching step data: \(error?.localizedDescription ?? "unknown error")")
                    continuation.resume(returning: nil)
                    return
                }
                
                var stepData: [[String: Any]] = []
                results.enumerateStatistics(from: self.startDate, to: self.endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let stepCount = Int(sum.doubleValue(for: HKUnit.count()))
                        
                        stepData.append([
                            "date": self.dateFormatter.string(from: statistics.startDate),
                            "step_count": stepCount,
                            "source": "HealthKit"
                        ])
                    }
                }
                
                print("Fetched \(stepData.count) daily step records")
                continuation.resume(returning: stepData)
            }
            
            healthStore.execute(query)
        }
    }
    
    // Fetch 30 days of sleep data
    private func fetchSleepData() async -> [[String: Any]]? {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            print("Sleep type not available")
            return nil
        }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    print("Error fetching sleep data: \(error)")
                    continuation.resume(returning: nil)
                    return
                }
                
                let sleepData = samples?
                    .compactMap { sample -> [String: Any]? in
                        guard let categorySample = sample as? HKCategorySample else {
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
                                "start_time": self.dateFormatter.string(from: categorySample.startDate),
                                "end_time": self.dateFormatter.string(from: categorySample.endDate),
                                "sleep_stage": sleepStageStr,
                                "source": categorySample.sourceRevision.source.name
                            ]
                        }
                        return nil
                    }
                
                print("Fetched \(sleepData?.count ?? 0) sleep records")
                continuation.resume(returning: sleepData)
            }
            
            healthStore.execute(query)
        }
    }
    
    // Fetch user characteristics
    private func fetchCharacteristics() async -> [String: Any] {
        var characteristics: [String: Any] = [:]
        
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
        
        return characteristics
    }
    
    // Fetch body measurements
    private func fetchBodyMeasurements() async -> [[String: Any]] {
        var bodyMeasurements: [[String: Any]] = []
        let timestamp = dateFormatter.string(from: Date())
        
        // Body Mass (Weight)
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
        
        return bodyMeasurements
    }
    
    // Helper function to fetch the latest quantity sample for a given type
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
    
    // Run risk analysis and recommendations after onboarding
    private func generateAnalysisAndRecommendations() async {
        do {
            print("Generating risk analysis after onboarding...")
            let riskAnalysis = try await NetworkManager.shared.calculateRiskAnalysis(deviceId: deviceId)
            
            if riskAnalysis.formatted_predictions.count > 0 {
                print("Generating recommendations based on risk analysis...")
                _ = try await NetworkManager.shared.getRecommendations(deviceId: deviceId)
                print("Recommendations generated successfully")
            } else {
                print("No predictions found in risk analysis, skipping recommendations")
            }
        } catch {
            print("Error during post-onboarding analysis: \(error)")
            // Continue anyway, as the main onboarding was successful
        }
    }
} 