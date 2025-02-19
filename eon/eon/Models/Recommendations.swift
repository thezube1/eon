import Foundation

struct Recommendation: Codable, Identifiable {
    let recommendation: String
    let explanation: String
    let frequency: String
    
    // Since the API doesn't provide an id, we'll generate one
    var id: String {
        // Create a unique id based on the recommendation content
        recommendation.hash.description
    }
}

struct RecommendationsByCategory: Codable {
    let Sleep: [Recommendation]
    let Steps: [Recommendation]
    let Heart_Rate: [Recommendation]
    
    enum CodingKeys: String, CodingKey {
        case Sleep
        case Steps
        case Heart_Rate = "Heart_Rate"
    }
}

struct RecommendationsResponse: Codable {
    let recommendations: RecommendationsByCategory
    let source_data: SourceData
    let user_id: String?
}

struct SourceData: Codable {
    let formatted_predictions: [RiskCluster]
    let soap_note: String
} 