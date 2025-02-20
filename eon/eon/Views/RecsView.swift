import SwiftUI

struct RecsView: View {
    @State private var recommendations: RecommendationsResponse?
    @State private var isLoading = false
    @State private var error: String?
    
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
                            RecommendationSection(
                                title: "Sleep",
                                icon: "bed.double.fill",
                                color: .indigo,
                                recommendations: recs.recommendations.Sleep,
                                onRecommendationUpdated: loadRecommendations
                            )
                            
                            // Steps recommendations
                            RecommendationSection(
                                title: "Steps",
                                icon: "figure.walk",
                                color: .green,
                                recommendations: recs.recommendations.Steps,
                                onRecommendationUpdated: loadRecommendations
                            )
                            
                            // Heart Rate recommendations
                            RecommendationSection(
                                title: "Heart Rate",
                                icon: "heart.fill",
                                color: .red,
                                recommendations: recs.recommendations.Heart_Rate,
                                onRecommendationUpdated: loadRecommendations
                            )
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
            
            // Recommendations
            ForEach(recommendations) { rec in
                RecommendationCard(
                    recommendation: rec,
                    color: color,
                    onRecommendationUpdated: onRecommendationUpdated
                )
            }
        }
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