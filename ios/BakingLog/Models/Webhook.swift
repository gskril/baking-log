import Foundation

struct Webhook: Identifiable, Codable {
    let id: String
    let url: String
    let hasSecret: Bool
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, url
        case hasSecret = "has_secret"
        case createdAt = "created_at"
    }
}

struct WebhookListResponse: Codable {
    let webhooks: [Webhook]
}
