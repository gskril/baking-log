import Foundation
import UIKit

actor APIClient {
    static let shared = APIClient()

    // Update this to your deployed worker URL
    private var baseURL: URL {
        let urlString = UserDefaults.standard.string(forKey: "api_base_url")
            ?? "http://localhost:8787"
        return URL(string: urlString)!
    }

    private var apiKey: String? {
        UserDefaults.standard.string(forKey: "api_key")
    }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String = "application/json") -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = method
        req.httpBody = body
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        if let key = apiKey {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - Bakes

    func listBakes(limit: Int = 50, offset: Int = 0) async throws -> [Bake] {
        let req = request("/api/bakes?limit=\(limit)&offset=\(offset)")
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try decoder.decode(BakeListResponse.self, from: data)
        return response.bakes
    }

    func getBake(id: String) async throws -> Bake {
        let req = request("/api/bakes/\(id)")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func createBake(_ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = request("/api/bakes", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func updateBake(id: String, _ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = request("/api/bakes/\(id)", method: "PUT", body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func deleteBake(id: String) async throws {
        let req = request("/api/bakes/\(id)", method: "DELETE")
        let _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Photos

    func uploadPhoto(bakeId: String, image: UIImage, caption: String? = nil) async throws -> Photo {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw APIError.invalidImage
        }

        let boundary = UUID().uuidString
        var body = Data()

        // Photo field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Caption field
        if let caption = caption {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append(caption.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = request("/api/bakes/\(bakeId)/photos", method: "POST", body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        req.httpBody = body

        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(Photo.self, from: data)
    }

    func deletePhoto(id: String) async throws {
        let req = request("/api/photos/\(id)", method: "DELETE")
        let _ = try await URLSession.shared.data(for: req)
    }

    func photoURL(for photoId: String) -> URL {
        baseURL.appendingPathComponent("/api/photos/\(photoId)/image")
    }
}

// MARK: - Payload Types

struct CreateBakePayload: Codable {
    let title: String
    let bakeDate: String
    let ingredients: String?
    let notes: String?
    let schedule: [ScheduleEntryPayload]?

    enum CodingKeys: String, CodingKey {
        case title, ingredients, notes, schedule
        case bakeDate = "bake_date"
    }
}

struct ScheduleEntryPayload: Codable {
    let time: String
    let action: String
    let note: String?
}

struct BakeListResponse: Codable {
    let bakes: [Bake]
}

enum APIError: LocalizedError {
    case invalidImage

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process image"
        }
    }
}
