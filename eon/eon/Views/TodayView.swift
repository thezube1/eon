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

// Added state for syncing indicator
@State private var isSyncing = false

var body: some View {
    TabView(selection: $selectedTab) {
        
        // --- "Today" tab ---
        content
            .tag(0)
            .tabItem {
                Image(systemName: "sun.max.fill")
                Text("Today")
            }
            // Request HealthKit authorization and then sync when the view appears
            .task {
                healthManager.requestAuthorization { success, error in
                    if success {
                        Task {
                            await syncData()
                        }
                    } else if let error = error {
                        print("HealthKit authorization failed: \(error)")
                    }
                }
            }
            // Allow pull-to-refresh to trigger a sync
            .refreshable {
                await syncData()
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
        stopTimer()
    }
}

// The main content view for the "Today" tab is wrapped in a ZStack to overlay the syncing indicator
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
                // Background rectangle (can be styled further)
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.clear)
                    .frame(width: min(geo.size.width, 250),
                           height: min(geo.size.height, 480))
                
                // The 48 segments in a vertical stack
                VStack(spacing: 0) {
                    ForEach(0..<segments.count, id: \.self) { i in
                        let segment = segments[i]
                        Rectangle()
                            .fill(segment.category.color())
                            .frame(height: min(geo.size.height, 480) / 48)
                            .onTapGesture {
                                selectedCategory = segment.category
                            }
                    }
                }
                .frame(width: min(geo.size.width, 250),
                       height: min(geo.size.height, 480))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                
                // Real-time indicator
                let progress = dayProgress(date: currentTime)
                let indicatorY = progress * min(geo.size.height, 480)
                
                Rectangle()
                    .fill(Color.black)
                    .frame(width: min(geo.size.width, 250), height: 2)
                    .offset(x: 0, y: indicatorY - 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: 500)
        .padding(.horizontal)
        
        Spacer()
    }
    .overlay(
        Group {
            if isSyncing {
                ZStack {
                    Color.black.opacity(0.3)
                        .edgesIgnoringSafeArea(.all)
                    ProgressView("Syncing...")
                        .padding()
                        .background(Color.white)
                        .cornerRadius(10)
                }
            }
        }
    )
}

// MARK: - Timer Methods

private func startTimer() {
    Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
        currentTime = Date()
    }
}

private func stopTimer() {
    // In a more advanced setup, store and invalidate the Timer.
}

// MARK: - Utility

/// Returns "Good Morning", "Good Afternoon", or "Good Evening" based on the hour
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

/// Returns the fraction (0 to 1) of how far we are into the current day
private func dayProgress(date: Date) -> CGFloat {
    let calendar = Calendar.current
    guard let startOfDay = calendar.dateInterval(of: .day, for: date)?.start else {
        return 0
    }
    let secondsSinceMidnight = date.timeIntervalSince(startOfDay)
    return CGFloat(secondsSinceMidnight / 86400)
}

/// Syncs data by calling the HealthManager's syncWithServer (see old HomeView.swift for reference)
private func syncData() async {
    isSyncing = true
    await healthManager.syncWithServer()
    isSyncing = false
}

}

struct TodayView_Previews: PreviewProvider { static var previews: some View { TodayView() .environmentObject(HealthManager()) } }
