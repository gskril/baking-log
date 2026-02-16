import Foundation
import SwiftUI

@MainActor
class BakeListViewModel: ObservableObject {
    @Published var bakes: [Bake] = []
    @Published var isLoading = false
    @Published var error: String?

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
}
