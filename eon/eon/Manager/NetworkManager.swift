// NetworkManager.swift
// Place this file in the same directory as your other Swift files

import Foundation
import UIKit

struct HealthMetrics: Codable {
    let heartRate: HeartRateData?
    let steps: StepData?
    let sleep: SleepData?
    
    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case steps
        case sleep
    }
}

struct HeartRateData: Codable {
    let timestamp: String
    let bpm: Double
    let source: String?
    let context: String?
}

struct StepData: Codable {
    let date: String
    let stepCount: Int
    let source: String?
    
    enum CodingKeys: String, CodingKey {
        case date
        case stepCount = "step_count"
        case source
    }
}

struct SleepData: Codable {
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

struct SyncStatus: Codable {
    let syncStatus: SyncTimes
    let lastSync: String?

    enum CodingKeys: String, CodingKey {
        case syncStatus = "sync_status"
        case lastSync = "last_sync"
    }

    // Add an explicit initializer to allow manual initialization
    init(syncStatus: SyncTimes, lastSync: String?) {
        self.syncStatus = syncStatus
        self.lastSync = lastSync
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        syncStatus = try container.decode(SyncTimes.self, forKey: .syncStatus)
        lastSync = try container.decodeIfPresent(String.self, forKey: .lastSync)
    }
}

struct SyncTimes: Codable {
    let heartRate: String?
    let steps: String?
    let sleep: String?
    
    enum CodingKeys: String, CodingKey {
        case heartRate = "heart_rate"
        case steps
        case sleep
    }
}

struct UserNoteResponse: Codable {
    let id: Int
    let deviceId: Int
    let note: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case deviceId = "device_id"
        case note
        case createdAt = "created_at"
    }
}

struct UserNotesResponse: Codable {
    let notes: [UserNoteResponse]
}

class NetworkManager {
    static let shared = NetworkManager()
    private let baseURL = "https://eon-758648273902.us-west1.run.app/api/health" // e.g., "http://your-api-domain.com"
    
    private init() {}
    
    func getSyncStatus(deviceId: String) async throws -> SyncStatus {
        let url = URL(string: "\(baseURL)/devices/\(deviceId)/sync-status")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 404:
                // If device not found, return empty sync status
                return SyncStatus(
                    syncStatus: SyncTimes(
                        heartRate: nil as String?,
                        steps: nil as String?,
                        sleep: nil as String?
                    ),
                    lastSync: nil as String?
                )
            case 200..<300:
                return try JSONDecoder().decode(SyncStatus.self, from: data)
            default:
                throw NetworkError.invalidResponse
            }
        }
        throw NetworkError.invalidResponse
    }
    
    func getLatestMetrics(deviceId: String) async throws -> HealthMetrics {
        let url = URL(string: "\(baseURL)/devices/\(deviceId)/latest")!
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(HealthMetrics.self, from: data)
    }
    
    func syncHealthData(deviceId: String, healthData: [String: Any]) async throws {
        print("Attempting to sync health data to URL: \(baseURL)/sync")
        let url = URL(string: "\(baseURL)/sync")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deviceInfo: [String: Any] = [
            "device_id": deviceId,
            "device_name": UIDevice.current.name,
            "device_model": UIDevice.current.model,
            "os_version": UIDevice.current.systemVersion
        ]
        
        var bodyDict = healthData
        bodyDict["device_info"] = deviceInfo
        
        request.httpBody = try JSONSerialization.data(withJSONObject: bodyDict)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Server error response: \(errorJson)")
            }
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    func createNote(deviceId: String, note: String) async throws {
        let url = URL(string: "\(baseURL)/notes/devices/\(deviceId)/notes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let noteData = ["note": note]
        request.httpBody = try JSONSerialization.data(withJSONObject: noteData)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("Server error response: \(errorJson)")
            }
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
    }
    
    func getNotes(deviceId: String) async throws -> [UserNoteResponse] {
        let url = URL(string: "\(baseURL)/notes/devices/\(deviceId)/notes")!
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.serverError(statusCode: httpResponse.statusCode)
        }
        
        let notesResponse = try JSONDecoder().decode(UserNotesResponse.self, from: data)
        return notesResponse.notes
    }
}

enum NetworkError: Error {
    case invalidResponse
    case invalidData
    case serverError(statusCode: Int)
}
