//
//  OnboardingView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var healthManager: HealthManager
    @StateObject private var onboardingManager = OnboardingManager()
    @AppStorage("HealthKitAuthorized") private var isAuthorized: Bool = false
    @AppStorage("HasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        // If already authorized and onboarded, show TodayView immediately
        if (isAuthorized || healthManager.isAuthorized) && hasCompletedOnboarding {
            TodayView()
        }
        // Otherwise, show onboarding content
        else {
            VStack(spacing: 20) {
                Text("Welcome to Eon")
                    .font(.largeTitle)
                    .bold()

                Text("We'd like to connect with Apple Health to track your steps, heart rate, sleep, and other health metrics like weight, height, and basic health information to provide you with better personalized recommendations.")
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)

                Button(action: {
                    // Start onboarding process
                    Task {
                        await startOnboarding()
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
                .disabled(onboardingManager.isOnboarding)
                
                if onboardingManager.isOnboarding {
                    VStack {
                        ProgressView(value: onboardingManager.onboardingProgress, total: 1.0)
                            .padding(.horizontal, 30)
                        
                        Text("Setting up your health data...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.top, 8)
                    }
                }
                
                if let error = onboardingManager.error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.top, 8)
                }
            }
            .padding()
            .onChange(of: onboardingManager.onboardingCompleted) { oldValue, newValue in
                if newValue {
                    // Mark onboarding as complete when finished
                    hasCompletedOnboarding = true
                    isAuthorized = true
                }
            }
        }
    }
    
    private func startOnboarding() async {
        // Start the onboarding process
        await onboardingManager.startOnboarding()
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        // Provide an environment object for previews
        OnboardingView()
            .environmentObject(HealthManager())
    }
}
