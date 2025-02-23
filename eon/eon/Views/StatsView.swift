import SwiftUI
import UIKit

struct StatsView: View {
    @State private var riskAnalysis: RiskAnalysisResponse? = nil
    @State private var isLoading = false
    @State private var error: String? = nil
    
    // State variables for dropdown toggles
    @State private var showPrimaryFactors = true
    @State private var showOtherFactors = false
    
    // Helper function to categorize diseases
    private func categorizedDiseases() -> (primary: [RiskCluster], other: [RiskCluster]) {
        guard let analysis = riskAnalysis else { return ([], []) }
        
        var primaryClusters: [RiskCluster] = []
        var otherClusters: [RiskCluster] = []
        var processedDiseases: Set<String> = []
        
        // First, create primary clusters
        let primaryCategories = ["Cardiovascular", "Sleep", "Endocrine"]
        
        for category in primaryCategories {
            var categoryDiseases: [Disease] = []
            
            for cluster in analysis.formatted_predictions {
                for disease in cluster.diseases {
                    let description = disease.description.lowercased()
                    let shouldInclude = (
                        category == "Cardiovascular" && (description.contains("heart") || description.contains("cardio") || description.contains("blood")) ||
                        category == "Sleep" && (description.contains("sleep") || description.contains("insomnia") || description.contains("apnea")) ||
                        category == "Endocrine" && (description.contains("diabetes") || description.contains("thyroid") || description.contains("hormone"))
                    )
                    
                    if shouldInclude && !processedDiseases.contains(disease.icd9_code) {
                        categoryDiseases.append(disease)
                        processedDiseases.insert(disease.icd9_code)
                    }
                }
            }
            
            if !categoryDiseases.isEmpty {
                primaryClusters.append(RiskCluster(
                    cluster_name: category,
                    diseases: categoryDiseases,
                    explanation: "Primary health factors related to \(category.lowercased()) conditions",
                    risk_level: categoryDiseases.count > 2 ? "High Risk" : "Medium Risk"
                ))
            }
        }
        
        // Then filter remaining diseases for other clusters
        otherClusters = analysis.formatted_predictions.compactMap { cluster -> RiskCluster? in
            let remainingDiseases = cluster.diseases.filter { !processedDiseases.contains($0.icd9_code) }
            guard !remainingDiseases.isEmpty else { return nil }
            
            return RiskCluster(
                cluster_name: cluster.cluster_name,
                diseases: remainingDiseases,
                explanation: cluster.explanation,
                risk_level: cluster.risk_level
            )
        }
        
        return (primaryClusters, otherClusters)
    }
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading risk analysis...")
                } else if let error = error {
                    ErrorView(message: error)
                } else if let _ = riskAnalysis {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Risk Analysis")
                                    .font(.largeTitle)
                                    .bold()
                                Text("Health Risk Categories")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            
                            let (primaryFactors, otherClusters) = categorizedDiseases()
                            
                            // Primary Health Factors Section
                            VStack {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showPrimaryFactors.toggle()
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "heart.text.square.fill")
                                            .foregroundColor(.blue)
                                        
                                        Text("Primary Health Factors")
                                            .font(.headline)
                                        
                                        Spacer()
                                        
                                        Text("\(primaryFactors.count)")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                        
                                        Image(systemName: showPrimaryFactors ? "chevron.up" : "chevron.down")
                                            .foregroundColor(.gray)
                                            .animation(.easeInOut, value: showPrimaryFactors)
                                    }
                                    .padding()
                                    .background(Color(.systemBackground))
                                    .cornerRadius(10)
                                    .shadow(color: Color.black.opacity(0.1), radius: 2)
                                }
                                
                                if showPrimaryFactors {
                                    ForEach(primaryFactors, id: \.cluster_name) { cluster in
                                        RiskClusterView(cluster: cluster)
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .padding(.horizontal)
                            
                            // Other Risk Clusters
                            if !otherClusters.isEmpty {
                                VStack {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showOtherFactors.toggle()
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "list.bullet.circle.fill")
                                                .foregroundColor(.gray)
                                            
                                            Text("Other Risk Factors")
                                                .font(.headline)
                                            
                                            Spacer()
                                            
                                            Text("\(otherClusters.count)")
                                                .font(.subheadline)
                                                .foregroundColor(.gray)
                                            
                                            Image(systemName: showOtherFactors ? "chevron.up" : "chevron.down")
                                                .foregroundColor(.gray)
                                                .animation(.easeInOut, value: showOtherFactors)
                                        }
                                        .padding()
                                        .background(Color(.systemBackground))
                                        .cornerRadius(10)
                                        .shadow(color: Color.black.opacity(0.1), radius: 2)
                                    }
                                    
                                    if showOtherFactors {
                                        ForEach(otherClusters, id: \.cluster_name) { cluster in
                                            RiskClusterView(cluster: cluster)
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                        .padding(.vertical)
                    }
                } else {
                    EmptyStateView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            Task {
                await loadRiskAnalysis()
            }
        }
    }
    
    private func loadRiskAnalysis() async {
        guard let deviceId = UIDevice.current.identifierForVendor?.uuidString else {
            self.error = "Could not determine device ID"
            return
        }
        
        isLoading = true
        error = nil
        
        do {
            riskAnalysis = try await NetworkManager.shared.getStoredRiskAnalysis(deviceId: deviceId)
        } catch {
            self.error = "Failed to load stored risk analysis: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct PrimaryFactorRow: View {
    let title: String
    let diseases: [Disease]
    let iconName: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: iconName)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(diseases.count)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            if diseases.isEmpty {
                Text("No diseases in this category")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                ForEach(diseases, id: \.icd9_code) { disease in
                    DiseaseRow(disease: disease)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 3)
        )
    }
}

struct RiskClusterView: View {
    let cluster: RiskCluster
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cluster header
            HStack {
                Text(cluster.cluster_name)
                    .font(.title2)
                    .bold()
                Spacer()
                RiskLevelBadge(riskLevel: cluster.risk_level)
            }
            
            // Diseases
            ForEach(cluster.diseases, id: \.icd9_code) { disease in
                DiseaseRow(disease: disease)
            }
            
            // Explanation
            Text(cluster.explanation)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
        .padding(.horizontal)
    }
}

struct DiseaseRow: View {
    let disease: Disease
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cross.case.fill")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(disease.description)
                    .font(.headline)
                Text("ICD-9: \(disease.icd9_code)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
    }
}

struct RiskLevelBadge: View {
    let riskLevel: String
    
    private var backgroundColor: Color {
        switch riskLevel.lowercased() {
        case "high risk":
            return Color.red.opacity(0.2)
        case "medium risk":
            return Color.orange.opacity(0.2)
        case "low risk":
            return Color.green.opacity(0.2)
        default:
            return Color.gray.opacity(0.2)
        }
    }
    
    private var textColor: Color {
        switch riskLevel.lowercased() {
        case "high risk":
            return Color.red
        case "medium risk":
            return Color.orange
        case "low risk":
            return Color.green
        default:
            return Color.gray
        }
    }
    
    var body: some View {
        Text(riskLevel)
            .font(.caption)
            .bold()
            .foregroundColor(textColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .clipShape(Capsule())
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            Text("No Risk Analysis Available")
                .font(.headline)
            Text("Check back later for your personalized health insights.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct ErrorView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.red)
            Text("Error")
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        StatsView()
    }
} 