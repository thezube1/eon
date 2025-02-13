//
//  HalfHourSegment.swift
//  eon
//
//  Created by Ashwin Mukherjee on 2/12/25.
//

import Foundation

/// Represents a single 30-minute block of the day, including its activity category.
struct HalfHourSegment {
    let startTime: Date
    var category: ActivityCategory
    // Potential additional metrics pulled from HealthKit in the future.
    // var heartRate: Double?
    // var stepCount: Double?
    // ...
}
