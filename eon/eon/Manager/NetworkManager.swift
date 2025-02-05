import Foundation

enum NetworkError: Error {
    case invalidURL
    case invalidResponse
    case decodingError
    case serverError(String)
}

struct SyncStatus: Codable {
    let deviceId: String
    let syncStatus: MetricStatus
    let lastSync: String?
    
    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case syncStatus = "sync_status"
        case lastSync = "last_sync"
    }
}

struct MetricStatus: Codable {
    let heartRate: String?
    let steps: String?
    let sleep: String?
    
    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case steps
        case sleep
    }
}

struct HealthMetrics: Codable {
    let heartRate: [HeartRateMetric]
    let steps: [StepMetric]
    let sleep: [SleepMetric]
    let metadata: MetricMetadata
    
    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case steps
        case sleep
        case metadata
    }
}

struct HeartRateMetric: Codable {
    let timestamp: String
    let bpm: Double
    let source: String?
    let context: String?
}

struct StepMetric: Codable {
    let date: String
    let stepCount: Int
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case date
        case stepCount = "step_count"
        case source
    }
}

struct SleepMetric: Codable {
    let startTime: String
    let endTime: String
    let sleepStage: String?
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case sleepStage = "sleep_stage"
        case source
    }
}

struct MetricMetadata: Codable {
    let startDate: String
    let endDate: String
    let deviceId: String
    
    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case endDate = "end_date"
        case deviceId = "device_id"
    }
}

class HealthService {
    private let baseURL = "http://your-api-base-url" // Replace with your actual API base URL
    private let deviceId: String
    
    init(deviceId: String) {
        self.deviceId = deviceId
    }
    
    // Get the last sync status for the device
    func getLastSyncStatus() async throws -> SyncStatus {
        let url = "\(baseURL)/devices/\(deviceId)/sync-status"
        guard let urlObj = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: urlObj)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse
        }
        
        do {
            return try JSONDecoder().decode(SyncStatus.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    // Get health metrics for a specific time interval
    func getMetrics(startDate: Date?, endDate: Date = Date()) async throws -> HealthMetrics {
        var urlComponents = URLComponents(string: "\(baseURL)/devices/\(deviceId)/metrics")!
        
        var queryItems = [URLQueryItem]()
        if let startDate = startDate {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "start_date", value: formatter.string(from: startDate)))
            queryItems.append(URLQueryItem(name: "end_date", value: formatter.string(from: endDate)))
        }
        
        urlComponents.queryItems = queryItems
        
        guard let url = urlComponents.url else {
            throw NetworkError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.invalidResponse
        }
        
        do {
            return try JSONDecoder().decode(HealthMetrics.self, from: data)
        } catch {
            throw NetworkError.decodingError
        }
    }
    
    // Sync health data to the server
    func syncHealthData(heartRate: [[String: Any]], steps: [[String: Any]], sleep: [[String: Any]]) async throws {
        let url = "\(baseURL)/sync"
        guard let urlObj = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        
        let deviceInfo: [String: Any] = [
            "device_id": deviceId,
            "device_name": UIDevice.current.name,
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion
        ]
        
        let payload: [String: Any] = [
            "device_info": deviceInfo,
            "heart_rate": heartRate,
            "steps": steps,
            "sleep": sleep
        ]
        
        var request = URLRequest(url: urlObj)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorJson["error"] as? String {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.invalidResponse
        }
    }
}
