//
//  HealthHeatmapView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 1/30/25.
//

import SwiftUI

struct HealthHeatmapView: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 7)) {
            ForEach(0..<30, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.purple.opacity(Double.random(in: 0.2...1)))
                    .frame(width: 20, height: 20)
            }
        }
    }
}
struct HealthHeatmapView_Previews: PreviewProvider {
    static var previews: some View {
        HealthHeatmapView()
    }
}
