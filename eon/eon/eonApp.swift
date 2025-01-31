//
//  eonApp.swift
//  eon
//
//  Created by Zubin Hydrie on 1/30/25.
//

import SwiftUI

@main
struct eonApp: App {
    @StateObject private var healthManager = HealthManager()
    @AppStorage("HealthKitAuthorized") private var isAuthorized: Bool = false

    var body: some Scene {
        WindowGroup {
            if isAuthorized {
                HomeView().environmentObject(healthManager)
            } else {
                OnboardingView()
                    .environmentObject(healthManager)
                    .onAppear {
                        isAuthorized = healthManager.isAuthorized
                    }
            }
        }
    }
}
