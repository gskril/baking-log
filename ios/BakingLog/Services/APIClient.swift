import Foundation

/// Typed errors for API requests, with user-readable descriptions.
enum APIError: LocalizedError {
    /// The base URL from Settings (plus path) doesn't parse as a URL.
    case invalidURL
    /// The server returned a non-2xx status. `message` is the worker's
    /// `{"error": string}` body when present.
    case httpError(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL — check Settings."
        case .httpError(let status, let message):
            let reason = message ?? HTTPURLResponse.localizedString(forStatusCode: status).capitalized
            return "\(reason) (\(status))"
        }
    }
}

extension Error {
    /// True for task-cancellation errors (e.g. `.task {}` cancelling an
    /// in-flight request on disappear) that shouldn't surface as user-facing
    /// failures.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError, urlError.code == .cancelled { return true }
        return false
    }
}

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

    private func request(_ path: String, method: String = "GET", body: Data? = nil, contentType: String? = "application/json") throws -> URLRequest {
        guard let url = URL(string: "\(baseURLString)\(path)") else {
            // The base URL is free-text user input from Settings — never crash on it.
            throw APIError.invalidURL
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

    /// Shape of the worker's error responses (see worker/src/routes/*.ts).
    private struct APIErrorBody: Decodable {
        let error: String
    }

    /// Throws a readable `APIError` for non-2xx responses, decoding the
    /// worker's `{"error": string}` body when present.
    private func checkResponse(_ data: Data, _ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorBody.self, from: data))?.error
            throw APIError.httpError(status: http.statusCode, message: message)
        }
    }

    // MARK: - Bakes

    func listBakes(limit: Int = 50, offset: Int = 0) async throws -> [Bake] {
        let req = try request("/api/bakes?limit=\(limit)&offset=\(offset)", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        let listResponse = try decoder.decode(BakeListResponse.self, from: data)
        return listResponse.bakes
    }

    func getBake(id: String) async throws -> Bake {
        let req = try request("/api/bakes/\(id)", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        return try decoder.decode(Bake.self, from: data)
    }

    func createBake(_ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = try request("/api/bakes", method: "POST", body: body)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        return try decoder.decode(Bake.self, from: data)
    }

    func updateBake(id: String, _ bake: CreateBakePayload) async throws -> Bake {
        let body = try JSONEncoder().encode(bake)
        let req = try request("/api/bakes/\(id)", method: "PUT", body: body)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        return try decoder.decode(Bake.self, from: data)
    }

    func deleteBake(id: String) async throws {
        let req = try request("/api/bakes/\(id)", method: "DELETE", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
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

        let req = try request(
            "/api/bakes/\(bakeId)/photos",
            method: "POST",
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )

        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        return try decoder.decode(Photo.self, from: data)
    }

    func deletePhoto(id: String) async throws {
        let req = try request("/api/photos/\(id)", method: "DELETE", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
    }

    // MARK: - Webhooks

    func listWebhooks() async throws -> [Webhook] {
        let req = try request("/api/webhooks", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        let listResponse = try decoder.decode(WebhookListResponse.self, from: data)
        return listResponse.webhooks
    }

    func createWebhook(url: String, secret: String?) async throws -> Webhook {
        var payload: [String: String] = ["url": url]
        if let secret { payload["secret"] = secret }
        let body = try JSONEncoder().encode(payload)
        let req = try request("/api/webhooks", method: "POST", body: body)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
        return try decoder.decode(Webhook.self, from: data)
    }

    func deleteWebhook(id: String) async throws {
        let req = try request("/api/webhooks/\(id)", method: "DELETE", contentType: nil)
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
    }

    func pushWebhooks() async throws {
        let req = try request("/api/webhooks/push", method: "POST", body: Data("{}".utf8))
        let (data, response) = try await session.data(for: req)
        try checkResponse(data, response)
    }

    /// Build a photo URL synchronously — safe to call from SwiftUI view bodies.
    /// Reads the base URL directly from shared UserDefaults to avoid actor isolation.
    /// Returns nil when the user-entered base URL doesn't parse; AsyncImage
    /// call sites render their placeholder for a nil URL.
    nonisolated func photoURL(for photoId: String) -> URL? {
        let raw = AppGroup.sharedDefaults.string(forKey: Self.baseURLKey) ?? Self.defaultBaseURL
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: "\(base)/api/photos/\(photoId)/image")
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
