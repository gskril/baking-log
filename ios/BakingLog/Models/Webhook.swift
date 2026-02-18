import Foundation

struct Webhook: Identifiable, Codable {
    let id: String
    let url: String
    let events: String
    let secret: String?
    let active: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, url, events, secret, active
        case createdAt = "created_at"
    }
}

struct WebhookListResponse: Codable {
    let webhooks: [Webhook]
}
