import SwiftUI

struct RecsView: View {
    @State private var recommendations: RecommendationsResponse?
    @State private var isLoading = false
    @State private var error: String?
    var focusedCluster: String? = nil
    
    // Helper functions to determine section visibility and focus
    private func shouldShowSleepSection() -> Bool {
        focusedCluster == nil || focusedCluster?.lowercased().contains("sleep") == true
    }
    
    private func shouldShowStepsSection() -> Bool {
        guard let cluster = focusedCluster?.lowercased() else { return true }
        return cluster.contains("activity") || 
               cluster.contains("exercise") || 
               cluster.contains("metabolic") ||
               cluster.contains("steps") ||
               cluster.contains("movement")
    }
    
    private func shouldShowHeartSection() -> Bool {
        guard let cluster = focusedCluster?.lowercased() else { return true }
        return cluster.contains("heart") || 
               cluster.contains("cardio") || 
               cluster.contains("vascular")
    }
    
    private func isSectionFocused(_ section: String) -> Bool {
        guard let cluster = focusedCluster?.lowercased() else { return false }
        switch section.lowercased() {
        case "sleep":
            return cluster.contains("sleep")
        case "steps":
            return cluster.contains("activity") || 
                   cluster.contains("exercise") || 
                   cluster.contains("metabolic") ||
                   cluster.contains("steps") ||
                   cluster.contains("movement")
        case "heart":
            return cluster.contains("heart") || 
                   cluster.contains("cardio") ||
                   cluster.contains("vascular")
        default:
            return false
        }
    }
    
    private func filterRecommendations(_ recommendations: [Recommendation]) -> [Recommendation] {
        guard let cluster = focusedCluster?.lowercased() else { 
            print("No focused cluster, showing all recommendations")
            return recommendations 
        }
        
        print("Filtering recommendations for cluster: \(cluster)")
        print("Available recommendations: \(recommendations.map { "[\($0.risk_cluster ?? "nil")] \($0.recommendation)" })")
        
        return recommendations.filter { rec in
            // If risk_cluster is nil, try to infer the category from the recommendation text
            let recommendationText = rec.recommendation.lowercased()
            let explanationText = rec.explanation.lowercased()
            let riskCluster = rec.risk_cluster?.lowercased() ?? ""
            
            // Keywords for activity/metabolic recommendations
            let activityKeywords = [
                "walk", "steps", "activity", "exercise", "movement",
                "stand", "active", "physical", "metabolic", "metabolism"
            ]
            
            switch cluster {
            case "cardiovascular":
                return riskCluster.contains("cardio") || 
                       riskCluster.contains("heart") || 
                       riskCluster.contains("vascular") ||
                       recommendationText.contains("heart") ||
                       recommendationText.contains("cardio") ||
                       recommendationText.contains("blood pressure") ||
                       explanationText.contains("heart") ||
                       explanationText.contains("cardio") ||
                       explanationText.contains("blood pressure")
            case "sleep":
                return riskCluster.contains("sleep") ||
                       recommendationText.contains("sleep") ||
                       recommendationText.contains("bed") ||
                       recommendationText.contains("rest") ||
                       explanationText.contains("sleep") ||
                       explanationText.contains("circadian")
            case "metabolic":
                return riskCluster.contains("metabolic") || 
                       riskCluster.contains("endocrine") ||
                       activityKeywords.contains(where: recommendationText.contains) ||
                       activityKeywords.contains(where: explanationText.contains) ||
                       recommendationText.contains("diabetes") ||
                       recommendationText.contains("thyroid") ||
                       explanationText.contains("blood sugar")
            default:
                return riskCluster.contains(cluster)
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
                                        isFocused: isSectionFocused("sleep")
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
                                        isFocused: isSectionFocused("steps")
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
                                        isFocused: isSectionFocused("heart")
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
                    .foregroundColor(color)
                Text(title)
                    .font(.title2)
                    .bold()
            }
            .padding(.bottom, 4)
            .opacity(isFocused ? 1.0 : 0.7)
            
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