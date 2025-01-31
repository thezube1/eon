//
//  HealthBoxPlot.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct HealthBoxPlot: View {
    let value: Double
    let maxValue: Double
    let metric: String
    let label: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(label)
                Spacer()
                Image(systemName: icon)
            }
            .font(.headline)

            ZStack {
                Rectangle().fill(Color.black.opacity(0.2)).frame(height: 4)
                Rectangle().fill(Color.purple).frame(width: CGFloat(value / maxValue) * 200, height: 4)
            }
            
            HStack {
                Text("\(Int(value)) \(metric)")
                Spacer()
                Text("\(Int(maxValue)) \(metric)")
            }
            .font(.caption)
        }
    }
}
