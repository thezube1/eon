import Foundation
import SwiftUI

struct Disease: Codable {
    let description: String
    let icd9_code: String
}

struct RiskCluster: Codable {
    let cluster_name: String
    let diseases: [Disease]
    let explanation: String
    let risk_level: String
}

struct Prediction: Codable {
    let description: String
    let icd9_code: String
    let probability: Double
}

struct RiskAnalysisResponse: Codable {
    let analysis_text_used: String
    let formatted_predictions: [RiskCluster]
    let metrics_summary: String?
    let soap_note: String?
    let predictions: [Prediction]
    let recommendation_counts: [String: Int]?
    
    var riskLevelColor: (String) -> Color {
        return { level in
            switch level.lowercased() {
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
    }
} 