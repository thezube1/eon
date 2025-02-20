import SwiftUI
import UIKit

struct StatsView: View {
    @State private var riskAnalysis: RiskAnalysisResponse? = nil
    @State private var isLoading = false
    @State private var error: String? = nil
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading risk analysis...")
                } else if let error = error {
                    ErrorView(message: error)
                } else if let analysis = riskAnalysis {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Header section
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Risk Analysis")
                                    .font(.largeTitle)
                                    .bold()
                                Text("Stored Risk Predictions")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                            
                            if analysis.formatted_predictions.isEmpty {
                                Text("No risk predictions available yet.")
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                    .padding()
                            } else {
                                // Risk clusters
                                ForEach(analysis.formatted_predictions, id: \.cluster_name) { cluster in
                                    RiskClusterView(cluster: cluster)
                                }
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
            riskAnalysis = try await NetworkManager.shared.getRiskAnalysis(deviceId: deviceId)
        } catch {
            self.error = "Failed to load stored risk analysis: \(error.localizedDescription)"
        }
        
        isLoading = false
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
            return Color.yellow.opacity(0.2)
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
            return Color.yellow
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