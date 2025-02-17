import SwiftUI

// 1) The data model for notes
struct UserNote: Identifiable {
    let id = UUID()
    var timestamp: Date
    var content: String
}

struct TodayView: View {
    
    @EnvironmentObject var healthManager: HealthManager

    // Tab selection
        @State private var selectedTab = 0
    
    // Existing states you might already have
    @State private var currentTime = Date()
    @State private var segments: [HalfHourSegment] = []
    @State private var selectedCategory: ActivityCategory? = nil
    
    // 2) New states for notes
    @State private var userNotes: [UserNote] = []        // The array of notes
    @State private var showNoteOverlay = false           // Toggle the overlay
    @State private var editingNote: UserNote? = nil      // Which note are we editing?
    @State private var noteText: String = ""             // The text in the overlay

    var body: some View {
            // 1) A TabView with three tabs
            TabView(selection: $selectedTab) {
                
                // --- TAB 1: Today ---
                mainContent
                    .tag(0)
                    .tabItem {
                        Image(systemName: "sun.max.fill")
                        Text("Today")
                    }
                
                // --- TAB 2: Recs (placeholder) ---
                Text("Recs View")
                    .tag(1)
                    .tabItem {
                        Image(systemName: "list.bullet.rectangle")
                        Text("Recs")
                    }
                
                // --- TAB 3: Stats (placeholder) ---
                Text("Stats View")
                    .tag(2)
                    .tabItem {
                        Image(systemName: "chart.bar.xaxis")
                        Text("Stats")
                    }
            }
            // 2) On appear, fetch your data as usual
            .onAppear {
                healthManager.dailySegments { newSegments in
                    self.segments = newSegments
                }
                startTimer()
            }
        }
        
        // MARK: - The bulk of your old "main layout" code
        private var mainContent: some View {
            ZStack {
                VStack {
                    // Top bar
                    HStack {
                        Button {
                            // profile
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.title)
                        }
                        Spacer()
                        Button {
                            // search
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.title)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    // Greeting or tapped category text
                    Text(
                        selectedCategory == nil
                        ? "\(greeting(for: currentTime)), Ashwin"
                        : descriptiveString(for: selectedCategory!)
                    )
                    .font(.largeTitle)
                    .bold()
                    .padding(.vertical, 8)
                    
                    // Spacer above the bar (optional)
                    Spacer()
                    
                    // Health bar geometry
                    GeometryReader { geo in
                        ZStack(alignment: .top) {
                            
                            // 48 segments, clipped corners, etc.
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
                            
                            // The black line indicator
                            let progress = dayProgress(for: currentTime)
                            let indicatorY = progress * min(geo.size.height, 480)
                            
                            Capsule()
                                .fill(Color(hex: "#393938"))
                                .frame(width: min(geo.size.width, 250) + 20, height: 3)
                                .offset(x: 0, y: indicatorY - 1.5)
                            
                            // Circles for notes
                            ForEach(userNotes) { note in
                                let noteProgress = dayProgress(for: note.timestamp)
                                let circleY = noteProgress * min(geo.size.height, 480)
                                
                                Circle()
                                    .fill(Color(hex: "#393938"))
                                    .frame(width: 10, height: 10)
                                    .offset(x: -160, y: circleY - 5)
                                    .onTapGesture {
                                        editingNote = note
                                        noteText = note.content
                                        showNoteOverlay = true
                                    }
                            }
                            
                            // The plus button near the right side
                            Button {
                                editingNote = UserNote(timestamp: Date(), content: "")
                                noteText = ""
                                showNoteOverlay = true
                            } label: {
                                Image(systemName: "plus.circle")
                                    .font(.title)
                                    .foregroundColor(.black)
                            }
                            .offset(x: min(geo.size.width, 250)/2 + 35,
                                    y: indicatorY - 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .frame(height: 500)
                    .padding(.horizontal)
                    
                    Spacer()
                }
                
                // Note overlay
                if showNoteOverlay {
                    // Dim background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            // Possibly close overlay on background tap
                        }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $noteText)
                            .frame(minHeight: 60, maxHeight: 120)
                            .cornerRadius(8)
                            .padding(8)
                            .background(Color.white)
                        
                        HStack {
                            Button {
                                deleteNote()
                            } label: {
                                Image(systemName: "trash")
                                    .font(.title2)
                                    .foregroundColor(.red)
                            }
                            
                            Spacer()
                            
                            Button {
                                saveNote()
                            } label: {
                                Image(systemName: "checkmark.circle")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                    .frame(width: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                }
            }
        }

    // MARK: - Timer stuff
    func startTimer() {
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            currentTime = Date()
        }
    }
    
    // MARK: - Greeting / Category Strings
    func greeting(for date: Date) -> String {
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
    
    // MARK: - dayProgress
    func dayProgress(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        guard let startOfDay = calendar.dateInterval(of: .day, for: date)?.start else {
            return 0
        }
        let secondsSinceMidnight = date.timeIntervalSince(startOfDay)
        return CGFloat(secondsSinceMidnight / 86400.0)
    }
    
    // MARK: - Saving / Deleting Notes
    func saveNote() {
        guard var note = editingNote else { return }
        // Update the note's content
        note.content = noteText
        note.timestamp = Date()  // If you want to "update" the timestamp each time.
        
        // If it's a brand new note (not in array), append; else update
        if let index = userNotes.firstIndex(where: { $0.id == note.id }) {
            // Update existing
            userNotes[index] = note
        } else {
            // Insert new
            userNotes.append(note)
        }
        // Reset overlay state
        editingNote = nil
        noteText = ""
        showNoteOverlay = false
    }
    
    func deleteNote() {
        guard let note = editingNote else { return }
        // Remove from array
        userNotes.removeAll { $0.id == note.id }
        // Reset overlay
        editingNote = nil
        noteText = ""
        showNoteOverlay = false
    }
}

struct TodayView_Previews: PreviewProvider { static var previews: some View { TodayView() .environmentObject(HealthManager()) } }
