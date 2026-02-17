import Foundation

actor APIClient {
    static let shared = APIClient()

    private static let defaultBaseURL = "http://localhost:8787"
    private static let baseURLKey = "api_base_url"
    private static let apiKeyKey = "api_key"

    private var baseURLString: String {
        let raw = AppGroup.sharedDefaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        // Strip trailing slash to avoid double-slashes when appending paths
        return raw.hasSuffix("/") ? String(raw.dropLast()) : raw
    }

    private var apiKey: String? {
        let key = AppGroup.sharedDefaults.string(forKey: Self.apiKeyKey)
        return (key?.isEmpty == true) ? nil : key
    }

    private let decoder = JSONDecoder()

    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String? = "application/json") -> URLRequest {
        guard let url = URL(string: "\(baseURLString)\(path)") else {
            // Fallback: shouldn't happen with valid settings, but avoids a crash
            fatalError("Invalid API URL: \(baseURLString)\(path)")
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.httpBody = body
        if let contentType {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let key = apiKey {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: - Bakes

    func listBakes(limit: Int = 50, offset: Int = 0) async throws -> [Bake] {
        let req = request("/api/bakes?limit=\(limit)&offset=\(offset)", contentType: nil)
        let (data, _) = try await URLSession.shared.data(for: req)
        let response = try decoder.decode(BakeListResponse.self, from: data)
        return response.bakes
    }

    func getBake(id: String) async throws -> Bake {
        let req = request("/api/bakes/\(id)", contentType: nil)
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
        let req = request("/api/bakes/\(id)", method: "DELETE", contentType: nil)
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Photos

    func uploadPhoto(bakeId: String, imageData: Data, caption: String? = nil) async throws -> Photo {
        let boundary = UUID().uuidString
        var body = Data()

        // Photo field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Caption field
        if let caption {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"caption\"\r\n\r\n".data(using: .utf8)!)
            body.append(caption.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        let req = request(
            "/api/bakes/\(bakeId)/photos",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(Photo.self, from: data)
    }

    func deletePhoto(id: String) async throws {
        let req = request("/api/photos/\(id)", method: "DELETE", contentType: nil)
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Webhooks

    struct PushResult: Codable {
        let ok: Bool
        let pushed: Int
    }

    func pushWebhooks(since: Date? = nil) async throws -> PushResult {
        let sinceISO = (since ?? Date(timeIntervalSinceNow: -86400)).ISO8601Format()
        let body = try JSONEncoder().encode(["since": sinceISO])
        let req = request("/api/webhooks/push", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return try decoder.decode(PushResult.self, from: data)
    }

    /// Build a photo URL synchronously — safe to call from SwiftUI view bodies.
    /// Reads the base URL directly from shared UserDefaults to avoid actor isolation.
    nonisolated func photoURL(for photoId: String) -> URL {
        let raw = AppGroup.sharedDefaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: "\(base)/api/photos/\(photoId)/image")!
    }
}

// MARK: - Payload Types

struct CreateBakePayload: Codable {
    let title: String
    let bakeDate: String
    let ingredientsText: String?
    let ingredients: [IngredientPayload]?
    let notes: String?
    let schedule: [ScheduleEntryPayload]?

    enum CodingKeys: String, CodingKey {
        case title, ingredients, notes, schedule
        case bakeDate = "bake_date"
        case ingredientsText = "ingredients_text"
    }
}

struct IngredientPayload: Codable {
    let name: String
    let amount: String
    let note: String?
}

struct ScheduleEntryPayload: Codable {
    let time: String
    let action: String
    let note: String?
}

struct BakeListResponse: Codable {
    let bakes: [Bake]
}
