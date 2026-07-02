import Foundation
import SwiftUI

@MainActor
class BakeListViewModel: ObservableObject {
    @Published var bakes: [Bake] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var hasMore = false
    @Published var error: String?
    @Published var isPushing = false
    @Published var pushResult: String?

    private let pageSize = 50

    /// Loads (or reloads) the first page. Used for initial load and pull-to-refresh.
    func load() async {
        isLoading = true
        error = nil
        do {
            let page = try await APIClient.shared.listBakes(limit: pageSize, offset: 0)
            bakes = page
            hasMore = page.count == pageSize
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// Fetches the next page and appends it. Safe to call repeatedly — guards
    /// against concurrent loads and skips entirely when the last page was short.
    func loadMore() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let page = try await APIClient.shared.listBakes(limit: pageSize, offset: bakes.count)
            // A refresh may have raced this request; drop any bakes we already have.
            let existingIds = Set(bakes.map(\.id))
            bakes.append(contentsOf: page.filter { !existingIds.contains($0.id) })
            hasMore = page.count == pageSize
        } catch {
            self.error = error.localizedDescription
        }
        isLoadingMore = false
    }

    func delete(at offsets: IndexSet) async {
        let ids = offsets.map { bakes[$0].id }
        bakes.remove(atOffsets: offsets)
        var deleteError: String?
        for id in ids {
            do {
                try await APIClient.shared.deleteBake(id: id)
            } catch {
                deleteError = "Couldn't delete bake. \(error.localizedDescription)"
            }
        }
        if let deleteError {
            await load()
            self.error = deleteError
        }
    }

    func pushWebhooks() async {
        isPushing = true
        pushResult = nil
        do {
            try await APIClient.shared.pushWebhooks()
            pushResult = "Webhooks pushed"
        } catch {
            pushResult = "Push failed: \(error.localizedDescription)"
        }
        isPushing = false
    }
}
