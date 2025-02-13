//
//  ActivityCategory.swift
//  eon
//
//  Created by Ashwin Mukherjee on 2/12/25.
//

import SwiftUI

/// Represents the type of sleep or activity for a given time block.
enum ActivityCategory {
    // Sleep
    case deepSleep      // #1565C0
    case lightSleep     // #42A5F5
    case remSleep       // #90CAF9

    // Activity (most to least active)
    case intense        // #66BB6A
    case moderate       // #81C784
    case light          // #A5D6A7
    case veryLight      // #C8E6C9
    case inactive       // #E8F5E9

    // No data
    case noData         // a neutral gray

    /// Returns the SwiftUI Color associated with each category.
    func color() -> Color {
        switch self {
        case .deepSleep:  return Color(hex: "#1565C0")
        case .lightSleep: return Color(hex: "#42A5F5")
        case .remSleep:   return Color(hex: "#90CAF9")

        case .intense:    return Color(hex: "#66BB6A")
        case .moderate:   return Color(hex: "#81C784")
        case .light:      return Color(hex: "#A5D6A7")
        case .veryLight:  return Color(hex: "#C8E6C9")
        case .inactive:   return Color(hex: "#E8F5E9")

        case .noData:     return Color.gray.opacity(0.4)
        }
    }
}
