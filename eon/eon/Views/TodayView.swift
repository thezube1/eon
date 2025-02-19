import SwiftUI

// Helper extension to safely access array elements
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// 1) The data model for notes
struct UserNote: Identifiable {
    let id: Int
    var timestamp: Date
    var content: String
    
    init(id: Int = -1, timestamp: Date = Date(), content: String) {
        self.id = id
        self.timestamp = timestamp
        self.content = content
    }
    
    init?(from response: UserNoteResponse) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        
        guard let date = formatter.date(from: response.createdAt) else {
            print("Failed to parse date: \(response.createdAt)")
            return nil
        }
        
        self.id = response.id
        self.timestamp = date
        self.content = response.note
    }
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
    @FocusState private var isNoteFieldFocused: Bool    // For keyboard focus
    @State private var showConfirmation = false         // For confirmation modal
    @State private var selectedTime: Date? = nil // Changed to optional to track if user has selected a time
    @State private var isDragging: Bool = false
    
    // Add state for syncing
    @State private var isSyncing = false
    
    // Timer for refreshing notes
    private let notesRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    
    var body: some View {
        TabView(selection: $selectedTab) {
            mainContent
                .tag(0)
                .tabItem {
                    Image(systemName: "sun.max.fill")
                    Text("Today")
                }
                .task {
                    // Initial sync when view appears
                    await syncData()
                }
                .refreshable {
                    // Allow pull-to-refresh to trigger a sync
                    await syncData()
                }
            
            Text("Recs View")
                .tag(1)
                .tabItem {
                    Image(systemName: "list.bullet.rectangle")
                    Text("Recs")
                }
            
            StatsView()
                .tag(2)
                .tabItem {
                    Image(systemName: "chart.bar.xaxis")
                    Text("Stats")
                }
        }
        .onAppear {
            print("TodayView appeared - Starting data load")
            healthManager.dailySegments { newSegments in
                self.segments = newSegments
            }
            startTimer()
            
            // Initial notes load
            Task {
                print("Starting initial loadNotes() task")
                await loadNotes()
            }
        }
        .onReceive(notesRefreshTimer) { _ in
            print("Timer triggered - refreshing notes")
            Task {
                await loadNotes()
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
        Task {
            do {
                // Get the device ID
                guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
                    print("No device ID available")
                    return
                }
                
                // Save the note to the server
                try await NetworkManager.shared.createNote(deviceId: deviceId, note: noteText)
                
                // Refresh notes from server
                await loadNotes()
                
                // Reset overlay state and show confirmation
                DispatchQueue.main.async {
                    showNoteOverlay = false
                    editingNote = nil
                    noteText = ""
                    showConfirmation = true
                    
                    // Dismiss confirmation after 3 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            showConfirmation = false
                        }
                    }
                }
                
            } catch {
                print("Error saving note: \(error)")
            }
        }
    }
    
    func loadNotes() async {
        print("loadNotes() function called")
        do {
            // Get the device ID
            guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
                print("No device ID available")
                return
            }
            print("Attempting to load notes for device: \(deviceId)")
            
            // Load notes from server
            let noteResponses = try await NetworkManager.shared.getNotes(deviceId: deviceId)
            print("Received \(noteResponses.count) notes from server")
            
            // Convert to UserNote objects
            let notes = noteResponses.compactMap { UserNote(from: $0) }
            print("Converted \(notes.count) valid notes")
            
            // Update the @State variable on the main thread
            DispatchQueue.main.async {
                self.userNotes = notes
                print("Updated userNotes array with \(notes.count) notes")
            }
            
        } catch {
            print("Error loading notes: \(error)")
            if let networkError = error as? NetworkError {
                print("Network error details: \(networkError)")
            }
        }
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
    
    // Update the updateSelectedTime function to handle clicks better
    private func updateSelectedTime(_ y: CGFloat, in geometry: GeometryProxy) {
        let maxHeight = min(geometry.size.height * 0.9, geometry.size.height - 40)
        let progress = max(0, min(1, y / maxHeight))
        let calendar = Calendar.current
        guard let startOfDay = calendar.dateInterval(of: .day, for: Date())?.start else { return }
        let secondsInDay: TimeInterval = 24 * 60 * 60
        let selectedSeconds = secondsInDay * Double(progress)
        let newSelectedTime = startOfDay.addingTimeInterval(selectedSeconds)
        
        // Update on main thread to avoid UI warnings
        DispatchQueue.main.async {
            selectedTime = newSelectedTime
            // Update selected category based on the time
            if let segment = segments[safe: Int(progress * 48)] {
                selectedCategory = segment.category
            }
        }
    }
    
    // New helper function to format time string
    private func timeString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    // Add sync function
    private func syncData() async {
        guard !isSyncing else { return }
        isSyncing = true
        await healthManager.syncWithServer()
        isSyncing = false
        
        // Refresh segments after sync
        healthManager.dailySegments { newSegments in
            self.segments = newSegments
        }
    }
    
    // MARK: - Main Content View
    private var mainContent: some View {
        GeometryReader { screenGeo in
            VStack {
                Spacer()
                Spacer()
                
                // Greeting or tapped category text
                Text(
                    selectedCategory == nil
                    ? "\(greeting(for: currentTime))"
                    : descriptiveString(for: selectedCategory!)
                )
                .font(.largeTitle)
                .bold()
                
                // Time display below greeting
                HStack(spacing: 12) {
                    Text(timeString(for: selectedTime ?? currentTime))
                        .font(.title2)
                        .foregroundColor(.gray)
                        .animation(.easeInOut, value: selectedTime)
                    
                    // Reset button appears when a time is selected
                    if selectedTime != nil {
                        Button(action: {
                            withAnimation {
                                selectedTime = nil
                                selectedCategory = nil
                            }
                        }) {
                            Text("Reset")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule()
                                        .fill(Color.black)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                                )
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                
                Spacer()
                
                // Health bar geometry
                GeometryReader { mainGeo in
                    ZStack(alignment: .top) {
                        // 48 segments, clipped corners, etc.
                        VStack(spacing: 0) {
                            ForEach(0..<segments.count, id: \.self) { i in
                                let segment = segments[i]
                                Rectangle()
                                    .fill(segment.category.color())
                                    .frame(height: min(mainGeo.size.height * 0.9, mainGeo.size.height - 40) / 48)
                            }
                        }
                        .frame(width: min(mainGeo.size.width, 250),
                               height: min(mainGeo.size.height * 0.9, mainGeo.size.height - 40))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    isDragging = true
                                    let localY = value.location.y
                                    updateSelectedTime(localY, in: mainGeo)
                                }
                                .onEnded { value in
                                    isDragging = false
                                    let localY = value.location.y
                                    updateSelectedTime(localY, in: mainGeo)
                                }
                        )
                        
                        // The black line indicator for current time
                        let progress = (selectedTime != nil) ? dayProgress(for: selectedTime!) : dayProgress(for: currentTime)
                        let indicatorY = progress * min(mainGeo.size.height * 0.9, mainGeo.size.height - 40)
                        
                        // Timeline bar
                        Capsule()
                            .fill(Color(hex: "#393938"))
                            .frame(width: min(mainGeo.size.width, 250) + 20, height: 3)
                            .offset(x: 0, y: indicatorY - 1.5)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        isDragging = true
                                        let localY = value.location.y
                                        updateSelectedTime(localY, in: mainGeo)
                                    }
                                    .onEnded { value in
                                        isDragging = false
                                        let localY = value.location.y
                                        updateSelectedTime(localY, in: mainGeo)
                                    }
                            )
                        
                        // Note indicators
                        let calendar = Calendar.current
                        let today = calendar.startOfDay(for: Date())
                        let todayNotes = userNotes.filter { calendar.startOfDay(for: $0.timestamp) == today }
                            .sorted { $0.timestamp < $1.timestamp }
                        
                        // First draw all lines (they'll be in the back)
                        ForEach(todayNotes) { note in
                            let noteProgress = dayProgress(for: note.timestamp)
                            let noteY = noteProgress * min(mainGeo.size.height * 0.9, mainGeo.size.height - 40)
                            
                            // Horizontal line
                            Capsule()
                                .fill(Color.black.opacity(0.2))
                                .frame(width: min(mainGeo.size.width, 250) + 20, height: 2)
                                .offset(x: 0, y: noteY - 1)
                                .zIndex(1)
                        }
                        
                        // Then draw all circles (they'll be in front)
                        ForEach(todayNotes) { note in
                            let noteProgress = dayProgress(for: note.timestamp)
                            let noteY = noteProgress * min(mainGeo.size.height * 0.9, mainGeo.size.height - 40)
                            
                            // Circle with note icon
                            Circle()
                                .fill(Color.black)
                                .frame(width: 24, height: 24)
                                .overlay(
                                    ZStack {
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                        Image(systemName: "note.text")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                    }
                                )
                                .offset(x: -((min(mainGeo.size.width, 250) + 20) / 2) - 15, y: noteY - 12)
                                .zIndex(Double(note.timestamp.timeIntervalSince1970))
                                .onTapGesture {
                                    editingNote = note
                                    noteText = note.content
                                    showNoteOverlay = true
                                }
                        }
                        
                        // The plus button near the right side
                        Button {
                            editingNote = UserNote(id: -1, timestamp: Date(), content: "")
                            noteText = ""
                            showNoteOverlay = true
                        } label: {
                            Image(systemName: "plus.circle")
                                .font(.title)
                                .foregroundColor(.black)
                        }
                        .offset(x: min(mainGeo.size.width, 250)/2 + 35,
                                y: indicatorY - 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(height: screenGeo.size.height * 0.85)
                .padding(.horizontal)
                
                Spacer()
                Spacer()
            }
            .overlay {
                if showNoteOverlay {
                    // Dim background
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showNoteOverlay = false
                        }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("How are you feeling?")
                            .font(.headline)
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                        
                        TextEditor(text: $noteText)
                            .frame(minHeight: 60, maxHeight: 120)
                            .cornerRadius(8)
                            .padding(8)
                            .background(Color.white)
                            .focused($isNoteFieldFocused)
                        
                        HStack {
                            if editingNote?.id != -1 {
                                Button {
                                    deleteNote()
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.title2)
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Spacer()
                            
                            // Cancel button
                            Button {
                                showNoteOverlay = false
                            } label: {
                                Text("Cancel")
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            
                            // Submit button
                            Button {
                                saveNote()
                            } label: {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 4)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 8)
                    }
                    .frame(width: 250)
                    .background(Color.white)
                    .cornerRadius(10)
                    .shadow(radius: 5)
                    .onAppear {
                        isNoteFieldFocused = true
                    }
                }
                
                if showConfirmation {
                    VStack {
                        Text("Thanks for checking in!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                Capsule()
                                    .fill(Color.black)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            )
                    }
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut, value: showConfirmation)
                }
                
                // Add syncing overlay
                if isSyncing {
                    ZStack {
                        Color.black.opacity(0.3)
                            .ignoresSafeArea()
                        VStack {
                            ProgressView()
                                .tint(.white)
                            Text("Syncing health data...")
                                .foregroundColor(.white)
                                .font(.headline)
                                .padding(.top, 8)
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.7))
                        )
                    }
                }
            }
        }
    }
}

struct TodayView_Previews: PreviewProvider {
    static var previews: some View {
        TodayView()
            .environmentObject(HealthManager())
    }
}
