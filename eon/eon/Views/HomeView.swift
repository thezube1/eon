//
//  HomeView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var healthManager: HealthManager  // Correctly reference the shared object

    var body: some View {
        VStack(spacing: 20) {
            // Top: Longevity Score
            VStack {
                Text("\(calculateLongevityScore())")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .background(Circle().fill(Color.purple).frame(width: 80, height: 80))
                
                Text("Weekly Longevity Score")
                    .font(.headline)
            }
            
            // Middle: Health Metric Box Plots
            VStack(spacing: 15) {
                HealthBoxPlot(value: healthManager.sleepHours, maxValue: 8, metric: "hours", label: "Sleep", icon: "moon.fill")
                HealthBoxPlot(value: healthManager.stepCount, maxValue: 8000, metric: "steps", label: "Steps", icon: "figure.walk")
                HealthBoxPlot(value: healthManager.heartRate, maxValue: 65, metric: "BPM", label: "Heart Rate", icon: "heart.fill")
            }
            .padding(.horizontal)
            
            // Bottom: Health Score Heatmap
            HealthHeatmapView()
            
            Spacer()
            
            // Navigation Bar (Placeholder)
            HStack {
                Image(systemName: "chart.bar")
                Spacer()
                Image(systemName: "house.fill").foregroundColor(.purple)
                Spacer()
                Image(systemName: "list.bullet")
            }
            .padding()
            .background(Color.white.shadow(radius: 2))
        }
        .padding()
    }
    
    func calculateLongevityScore() -> Int {
        let sleepScore = min((healthManager.sleepHours / 8) * 100, 100)
        let stepScore = min((healthManager.stepCount / 8000) * 100, 100)
        let hrScore = max(100 - (abs(65 - healthManager.heartRate) * 2), 0)
        return Int((sleepScore + stepScore + hrScore) / 3)
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView()
    }
}

