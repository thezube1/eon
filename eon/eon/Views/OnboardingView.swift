//
//  OnboardingView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var healthManager: HealthManager
    @AppStorage("HealthKitAuthorized") private var isAuthorized: Bool = false
    @State private var isSyncing = false
    @State private var error: String? = nil

    var body: some View {
        // 1) If already authorized, show TodayView immediately.
        //
        // This checks both:
        // - The local @AppStorage flag (isAuthorized)
        // - The HealthManager's published isAuthorized (healthManager.isAuthorized)
        // If either is true, we skip onboarding entirely.
        if isAuthorized || healthManager.isAuthorized {
            TodayView()
        }
        // 2) Otherwise, show onboarding content
        else {
            VStack(spacing: 20) {
                Text("Welcome to Eon")
                    .font(.largeTitle)
                    .bold()

                Text("We'd like to connect with Apple Health to track your steps, heart rate, and sleep.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Button(action: {
                    // When user taps "Connect," we request HealthKit authorization
                    healthManager.requestAuthorization { success, _ in
                        if success {
                            // Update local flag so we skip onboarding next time
                            isAuthorized = true
                            // Perform initial sync and generate recommendations
                            Task {
                                await performInitialSync()
                            }
                        }
                    }
                }) {
                    Text("Connect Apple Health")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                .padding(.horizontal, 30)
                
                if isSyncing {
                    VStack {
                        ProgressView()
                        Text("Setting up your health data...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                }
                
                if let error = error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
    }
    
    private func performInitialSync() async {
        isSyncing = true
        error = nil
        
        do {
            // 1. First sync health data
            await healthManager.syncWithServer()
            
            // 2. Get device ID
            guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
                error = "Could not determine device ID"
                return
            }
            
            // 3. Generate risk analysis
            _ = try await NetworkManager.shared.getRecommendations(deviceId: deviceId)
            
            isSyncing = false
        } catch {
            self.error = "Failed to sync: \(error.localizedDescription)"
            isSyncing = false
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide an environment object for previews
        OnboardingView()
            .environmentObject(HealthManager())
    }
}
