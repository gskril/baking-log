import Foundation
import SwiftUI

@MainActor
class BakeListViewModel: ObservableObject {
    @Published var bakes: [Bake] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isPushing = false
    @Published var pushResult: String?

    func load() async {
        isLoading = true
        error = nil
        do {
            bakes = try await APIClient.shared.listBakes()
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    func delete(at offsets: IndexSet) async {
        let ids = offsets.map { bakes[$0].id }
        bakes.remove(atOffsets: offsets)
        for id in ids {
            try? await APIClient.shared.deleteBake(id: id)
        }
    }

    func pushWebhooks() async {
        isPushing = true
        pushResult = nil
        do {
            let result = try await APIClient.shared.pushWebhooks()
            pushResult = "Pushed \(result.pushed) bake\(result.pushed == 1 ? "" : "s")"
        } catch {
            pushResult = "Push failed: \(error.localizedDescription)"
        }
        isPushing = false
    }
}
