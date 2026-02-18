import Foundation

@MainActor
class WebhookSettingsViewModel: ObservableObject {
    @Published var webhooks: [Webhook] = []
    @Published var isLoading = false
    @Published var error: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            webhooks = try await APIClient.shared.listWebhooks()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func add(url: String, secret: String?) async {
        error = nil
        do {
            let webhook = try await APIClient.shared.createWebhook(url: url, secret: secret)
            webhooks.insert(webhook, at: 0)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func delete(at offsets: IndexSet) async {
        let ids = offsets.map { webhooks[$0].id }
        webhooks.remove(atOffsets: offsets)
        for id in ids {
            try? await APIClient.shared.deleteWebhook(id: id)
        }
    }
}
