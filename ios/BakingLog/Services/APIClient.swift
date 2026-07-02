import Foundation

actor APIClient {
    static let shared = APIClient()

    private static let defaultBaseURL = "https://baking-log.gregskril.workers.dev"
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

    // Fail fast when connectivity is bad — the default 60s request timeout
    // leaves the UI spinning with no feedback.
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

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
        let (data, _) = try await session.data(for: req)
        let response = try decoder.decode(BakeListResponse.self, from: data)
        return response.bakes
    }

    func getBake(id: String) async throws -> Bake {
        let req = request("/api/bakes/\(id)", contentType: nil)
        let (data, _) = try await session.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func createBake(_ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = request("/api/bakes", method: "POST", body: body)
        let (data, _) = try await session.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func updateBake(id: String, _ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = request("/api/bakes/\(id)", method: "PUT", body: body)
        let (data, _) = try await session.data(for: req)
        return try decoder.decode(Bake.self, from: data)
    }

    func deleteBake(id: String) async throws {
        let req = request("/api/bakes/\(id)", method: "DELETE", contentType: nil)
        _ = try await session.data(for: req)
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

        let (data, _) = try await session.data(for: req)
        return try decoder.decode(Photo.self, from: data)
    }

    func deletePhoto(id: String) async throws {
        let req = request("/api/photos/\(id)", method: "DELETE", contentType: nil)
        _ = try await session.data(for: req)
    }

    // MARK: - Webhooks

    func listWebhooks() async throws -> [Webhook] {
        let req = request("/api/webhooks", contentType: nil)
        let (data, _) = try await session.data(for: req)
        let response = try decoder.decode(WebhookListResponse.self, from: data)
        return response.webhooks
    }

    func createWebhook(url: String, secret: String?) async throws -> Webhook {
        var payload: [String: String] = ["url": url]
        if let secret { payload["secret"] = secret }
        let body = try JSONEncoder().encode(payload)
        let req = request("/api/webhooks", method: "POST", body: body)
        let (data, _) = try await session.data(for: req)
        return try decoder.decode(Webhook.self, from: data)
    }

    func deleteWebhook(id: String) async throws {
        let req = request("/api/webhooks/\(id)", method: "DELETE", contentType: nil)
        _ = try await session.data(for: req)
    }

    func pushWebhooks() async throws {
        let req = request("/api/webhooks/push", method: "POST", body: Data("{}".utf8))
        _ = try await session.data(for: req)
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
    let title: String?
    let bakeDate: String
    let ingredients: [IngredientPayload]?
    let notes: String?
    let schedule: [ScheduleEntryPayload]?

    enum CodingKeys: String, CodingKey {
        case title, ingredients, notes, schedule
        case bakeDate = "bake_date"
    }
}

struct IngredientPayload: Codable {
    let name: String
    let amountValue: Double?
    let unit: String?
    let note: String?

    enum CodingKeys: String, CodingKey {
        case name, unit, note
        case amountValue = "amount_value"
    }
}

struct ScheduleEntryPayload: Codable {
    /// Local wall-clock ISO 8601 ("yyyy-MM-ddTHH:mm:ss"), no timezone.
    let occursAt: String?
    let action: String
    let note: String?

    enum CodingKeys: String, CodingKey {
        case action, note
        case occursAt = "occurs_at"
    }
}

struct BakeListResponse: Codable {
    let bakes: [Bake]
}
