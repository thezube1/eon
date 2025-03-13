import SwiftUI

struct RecsView: View {
    @State private var recommendations: RecommendationsResponse?
    @State private var isLoading = false
    @State private var error: String?
    @State private var selectedCategory: String = "All"
    var focusedCluster: String? = nil
    
    private let categories = ["All", "Sleep", "Steps", "Heart Rate"]
    
    // Helper function to convert cluster name to category
    private func categoryForCluster(_ cluster: String?) -> String {
        guard let cluster = cluster?.lowercased() else { return "All" }
        
        // Direct mapping from StatsView categories
        switch cluster {
        case "cardiovascular":
            return "Heart Rate"
        case "sleep":
            return "Sleep"
        case "metabolic":
            return "Steps"
        default:
            // For other cases, use keyword matching
            if cluster.contains("sleep") {
                return "Sleep"
            } else if cluster.contains("cardio") || cluster.contains("heart") || cluster.contains("vascular") {
                return "Heart Rate"
            } else if cluster.contains("metabolic") || cluster.contains("activity") || cluster.contains("exercise") {
                return "Steps"
            }
            return "All"
        }
    }
    
    // Helper functions to determine section visibility and focus
    private func shouldShowSleepSection() -> Bool {
        selectedCategory == "All" || selectedCategory == "Sleep"
    }
    
    private func shouldShowStepsSection() -> Bool {
        selectedCategory == "All" || selectedCategory == "Steps"
    }
    
    private func shouldShowHeartSection() -> Bool {
        selectedCategory == "All" || selectedCategory == "Heart Rate"
    }
    
    private func isSectionFocused(_ section: String) -> Bool {
        selectedCategory == section || selectedCategory == "All"
    }
    
    private func filterRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        // If no focused cluster or All category selected, show all recommendations
        if focusedCluster == nil || selectedCategory == "All" {
            return recommendations
        }
        
        // Use the selected category for filtering instead of the focused cluster
        return recommendations.filter { rec in
            let recommendationText = rec.recommendation.lowercased()
            let explanationText = rec.explanation.lowercased()
            let riskCluster = rec.risk_cluster?.lowercased() ?? ""
            
            switch selectedCategory {
            case "Heart Rate":
                return riskCluster.contains("cardio") || 
                       riskCluster.contains("heart") || 
                       riskCluster.contains("vascular") ||
                       recommendationText.contains("heart") ||
                       recommendationText.contains("cardio") ||
                       recommendationText.contains("blood pressure") ||
                       explanationText.contains("heart") ||
                       explanationText.contains("cardio") ||
                       explanationText.contains("blood pressure")
            case "Sleep":
                return riskCluster.contains("sleep") ||
                       recommendationText.contains("sleep") ||
                       recommendationText.contains("bed") ||
                       recommendationText.contains("rest") ||
                       explanationText.contains("sleep") ||
                       explanationText.contains("circadian")
            case "Steps":
                let activityKeywords = [
                    "walk", "steps", "activity", "exercise", "movement",
                    "stand", "active", "physical", "metabolic", "metabolism"
                ]
                return activityKeywords.contains { keyword in
                    riskCluster.contains(keyword) ||
                    recommendationText.contains(keyword) ||
                    explanationText.contains(keyword)
                }
            default:
                return true
            }
        }
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading recommendations...")
                } else if let error = error {
                    ErrorView(message: error)
                } else if let recs = recommendations {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Category Filter
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(categories, id: \.self) { category in
                                    Text(category)
                                }
                            }
                            .pickerStyle(SegmentedPickerStyle())
                            .padding(.horizontal)
                            
                            // Sleep recommendations
                            if shouldShowSleepSection() {
                                let sleepRecs = filterRecommendations(recs.recommendations.Sleep)
                                if !sleepRecs.isEmpty {
                                    RecommendationSection(
                                        title: "Sleep",
                                        icon: "bed.double.fill",
                                        color: .indigo,
                                        recommendations: sleepRecs,
                                        onRecommendationUpdated: loadRecommendations,
                                        isFocused: isSectionFocused("Sleep")
                                    )
                                }
                            }
                            
                            // Steps recommendations
                            if shouldShowStepsSection() {
                                let stepsRecs = filterRecommendations(recs.recommendations.Steps)
                                if !stepsRecs.isEmpty {
                                    RecommendationSection(
                                        title: "Steps",
                                        icon: "figure.walk",
                                        color: .green,
                                        recommendations: stepsRecs,
                                        onRecommendationUpdated: loadRecommendations,
                                        isFocused: isSectionFocused("Steps")
                                    )
                                }
                            }
                            
                            // Heart Rate recommendations
                            if shouldShowHeartSection() {
                                let heartRecs = filterRecommendations(recs.recommendations.Heart_Rate)
                                if !heartRecs.isEmpty {
                                    RecommendationSection(
                                        title: "Heart Rate",
                                        icon: "heart.fill",
                                        color: .red,
                                        recommendations: heartRecs,
                                        onRecommendationUpdated: loadRecommendations,
                                        isFocused: isSectionFocused("Heart Rate")
                                    )
                                }
                            }
                        }
                        .padding()
                    }
                } else {
                    RecsEmptyStateView()
                }
            }
            .navigationTitle("Recommendations")
        }
        .onAppear {
            // Set initial category based on focusedCluster
            selectedCategory = categoryForCluster(focusedCluster)
            Task {
                await loadRecommendations()
            }
        }
    }
    
    func loadRecommendations() async {
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
            error = "Could not determine device ID"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            recommendations = try await NetworkManager.shared.getStoredRecommendations(deviceId: deviceId)
        } catch {
            self.error = "Failed to load recommendations: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct RecommendationSection: View {
    let title: String
    let icon: String
    let color: Color
    let recommendations: [Recommendation]
    let onRecommendationUpdated: () async -> Void
    let isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.white)
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(color)
            )
            .opacity(isFocused ? 1.0 : 0.9)
            
            // Recommendations
            ForEach(recommendations) { rec in
                RecommendationCard(
                    recommendation: rec,
                    color: color,
                    onRecommendationUpdated: onRecommendationUpdated
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(
                    color: isFocused ? color.opacity(0.3) : Color.black.opacity(0.1),
                    radius: isFocused ? 8 : 5,
                    x: 0,
                    y: 2
                )
        )
        .scaleEffect(isFocused ? 1.02 : 1.0)
        .animation(.spring(response: 0.3), value: isFocused)
    }
}

struct RecommendationCard: View {
    let recommendation: Recommendation
    let color: Color
    let onRecommendationUpdated: () async -> Void
    @State private var isUpdating = false
    
    var body: some View {
        Button(action: {
            toggleAcceptance()
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text(recommendation.recommendation)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(recommendation.explanation)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundColor(color)
                        Text(recommendation.frequency)
                            .font(.caption)
                            .foregroundColor(color)
                    }
                }
                
                Spacer()
                
                if isUpdating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } else {
                    Image(systemName: recommendation.accepted == true ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(color)
                        .font(.title2)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(recommendation.id == nil)  // Disable interaction if no ID
    }
    
    private func toggleAcceptance() {
        guard !isUpdating, let id = recommendation.id else { return }
        
        isUpdating = true
        Task {
            do {
                try await NetworkManager.shared.updateRecommendationAcceptance(
                    recommendationId: id,
                    accepted: !(recommendation.accepted ?? false)
                )
                // Refresh recommendations after update
                await onRecommendationUpdated()
            } catch {
                print("Error updating recommendation acceptance: \(error)")
            }
            isUpdating = false
        }
    }
}

struct RecsEmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No Recommendations Available")
                .font(.headline)
            Text("Check back later for personalized health recommendations.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct RecsView_Previews: PreviewProvider {
    static var previews: some View {
        RecsView()
    }
} 