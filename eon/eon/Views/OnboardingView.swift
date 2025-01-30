//
//  OnboardingView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var healthManager = HealthManager()
    @State private var authorizationStatus: String = "Not Requested"

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Eon")
                .font(.largeTitle)
                .bold()
                .multilineTextAlignment(.center)

            Text("We’d like to connect with Apple Health to track your steps, heart rate, and sleep.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Text("Authorization Status: \(authorizationStatus)")
                .foregroundColor(healthManager.isAuthorized ? .green : .red)

            Button(action: {
                healthManager.requestAuthorization { success, error in
                    DispatchQueue.main.async {
                        if success {
                            authorizationStatus = "Authorized"
                        } else {
                            authorizationStatus = "Denied or Error"
                        }
                    }
                }
            }) {
                Text(healthManager.isAuthorized ? "HealthKit Connected" : "Connect Apple Health")
                    .font(.headline)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(healthManager.isAuthorized ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .disabled(healthManager.isAuthorized) // prevents re-tapping after authorization
            .padding(.horizontal, 30)
        }
        .padding()
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
