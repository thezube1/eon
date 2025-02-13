//
//  TodayView.swift
//  eon
//
//  Created by Ashwin Mukherjee on 2/12/25.
//

import SwiftUI

struct TodayView: View {
    
    @EnvironmentObject var healthManager: HealthManager
    
    // Timer for moving real-time indicator
    @State private var currentTime = Date()
    
    // We’ll store the day’s segments here
    @State private var segments: [HalfHourSegment] = []
    
    // For tab bar selection (if using TabView)
    @State private var selectedTab = 0
    
    @State private var selectedCategory: ActivityCategory? = nil
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            // --- "Today" tab ---
            content
                .tag(0)
                .tabItem {
                    Image(systemName: "sun.max.fill")
                    Text("Today")
                }
            
            // --- "Recs" tab (placeholder) ---
            Text("Recs View")
                .tag(1)
                .tabItem {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Recs")
                }
            
            // --- "Stats" tab (placeholder) ---
            Text("Stats View")
                .tag(2)
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Stats")
                }
        }
        .onAppear {
            healthManager.dailySegments { newSegments in
                self.segments = newSegments
            }
            startTimer()
        }
        .onDisappear {
            // In case you only want the indicator to move while on this screen
            stopTimer()
        }
    }
    
    private var content: some View {
        VStack {
            // --- Top bar ---
            HStack {
                // Profile button
                Button(action: {
                    // handle profile button action
                }) {
                    Image(systemName: "person.crop.circle")
                        .font(.title)
                }
                
                Spacer()
                
                // Search button
                Button(action: {
                    // handle search button action
                }) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            // --- Greeting text ---
            Text(
                selectedCategory == nil
                ? "\(greeting(for: currentTime)), Ashwin"
                : descriptiveString(for: selectedCategory!)
            )
            .font(.largeTitle)
            .bold()
            .padding(.vertical, 8)

            
            // --- Health Bar / 48 segments ---
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    // The entire rectangular area
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.clear) // or a background color if you prefer
                        .frame(width: min(geo.size.width, 250), // preserve 250 max width
                               height: min(geo.size.height, 480))
                        .border(Color.clear)
                    
                    // The 48 segments in a vertical stack
                    VStack(spacing: 0) {
                        ForEach(0..<segments.count, id: \.self) { i in
                            let segment = segments[i]
                            Rectangle()
                                .fill(segment.category.color())
                                .frame(height: min(geo.size.height, 480) / 48)
                                .onTapGesture {
                                    // On tap, update the selected category
                                    selectedCategory = segment.category
                                }
                        }
                    }
                    .frame(width: min(geo.size.width, 250),
                           height: min(geo.size.height, 480))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    // Real-time indicator
                    // figure out how far we are into the day
                    let progress = dayProgress(date: currentTime) // range 0...1
                    // The Y position = total height * progress
                    let indicatorY = progress * min(geo.size.height, 480)
                    
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: min(geo.size.width, 250), height: 2)
                        .offset(x: 0, y: indicatorY - 1) // shift by half its thickness
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(height: 500) // Provide some fixed-ish height for the geometry reader
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    // MARK: - Timer Methods
    
    private func startTimer() {
        // Update every 30 seconds or even every 1 second for smoothness
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    private func stopTimer() {
        // In a more advanced setup, store the Timer in a @State var so you can invalidate it.
    }
    
    // MARK: - Utility
    
    /// Returns "Good Morning", "Good Afternoon", or "Good Evening" based on hour
    private func greeting(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<12:  return "Good Morning"
        case 12..<17: return "Good Afternoon"
        default:      return "Good Evening"
        }
    }
    
    func descriptiveString(for category: ActivityCategory) -> String {
        switch category {
        case .deepSleep:  return "Deep Sleep"
        case .lightSleep: return "Light Sleep"
        case .remSleep:   return "REM Sleep"
        case .intense:    return "Intense Activity"
        case .moderate:   return "Moderate Activity"
        case .light:      return "Light Activity"
        case .veryLight:  return "Very Light Activity"
        case .inactive:   return "Inactive"
        case .noData:     return "No Data"
        }
    }
    
    /// Returns a fraction (0 to 1) of how far we are into the current day
    private func dayProgress(date: Date) -> CGFloat {
        let calendar = Calendar.current
        guard let startOfDay = calendar.dateInterval(of: .day, for: date)?.start else {
            return 0
        }
        let secondsSinceMidnight = date.timeIntervalSince(startOfDay)
        return CGFloat(secondsSinceMidnight / 86400) // 24 * 60 * 60
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
            .environmentObject(HealthManager())
    }

}
