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

    var body: some View {
        VStack(spacing: 20) {
            Text("Welcome to Eon")
                .font(.largeTitle)
                .bold()
            
            Text("We’d like to connect with Apple Health to track your steps, heart rate, and sleep.")
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)

            Button(action: {
                healthManager.requestAuthorization { success, _ in
                    if success {
                        isAuthorized = true
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
        }
        .padding()
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
    }
}
