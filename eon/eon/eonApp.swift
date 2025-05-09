//
//  eonApp.swift
//  eon
//
//  Created by Zubin Hydrie on 1/30/25.
//

import SwiftUI

@main
struct eonApp: App {
    @StateObject var healthManager = HealthManager()
    @StateObject var onboardingManager = OnboardingManager()

    var body: some Scene {
        WindowGroup {
            OnboardingView()
                .environmentObject(healthManager)
                .environmentObject(onboardingManager)
        }
    }
}
