import Foundation

struct Recommendation: Codable, Identifiable {
    let id: Int?
    let recommendation: String
    let explanation: String
    let frequency: String
    let accepted: Bool?
    
    var identifiableId: Int {
        return id ?? -1
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
    let source_data: SourceData?
    let user_id: String?
    
    enum CodingKeys: String, CodingKey {
        case recommendations
        case source_data
        case user_id
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recommendations = try container.decode(RecommendationsByCategory.self, forKey: .recommendations)
        source_data = try container.decodeIfPresent(SourceData.self, forKey: .source_data) ?? SourceData(formatted_predictions: nil, soap_note: nil)
        user_id = try container.decodeIfPresent(String.self, forKey: .user_id)
    }
}

struct SourceData: Codable {
    let formatted_predictions: [RiskCluster]?
    let soap_note: String?
} 