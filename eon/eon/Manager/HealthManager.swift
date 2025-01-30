//
//  HealthManager.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import Foundation
import HealthKit

class HealthManager: ObservableObject {
    let healthStore = HKHealthStore()
    
    @Published var isAuthorized: Bool = false

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        
        if let stepCountType = HKObjectType.quantityType(forIdentifier: .stepCount) {
            types.insert(stepCountType)
        }
        
        if let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) {
            types.insert(heartRateType)
        }
        
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }
        
        return types
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        #if targetEnvironment(simulator)
        print("⚠️ HealthKit is not supported on the simulator. Skipping authorization.")
        DispatchQueue.main.async {
            self.isAuthorized = false
        }
        completion(false, nil)
        return
        #endif
        
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
            }
            completion(success, error)
        }
    }
}
