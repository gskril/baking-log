import Foundation
import Network

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isOnline = true
    @Published var pendingBakes: [PendingBake] = []
    @Published var isSyncing = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bakinglog.networkmonitor")
    private static let storageKey = "pending_bakes"

    struct PendingBake: Identifiable, Codable {
        let id: String
        let payload: CreateBakePayload
        let imageDataItems: [Data]
        let createdLocally: Date

        var displayDate: String {
            let parts = payload.bakeDate.split(separator: "-")
            guard parts.count == 3,
                  let month = Int(parts[1]),
                  let day = Int(parts[2]) else {
                return payload.bakeDate
            }
            let year = String(parts[0].suffix(2))
            return "\(month)/\(day)/\(year)"
        }
    }

    private init() {
        loadPending()
        startMonitoring()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = path.status == .satisfied
                if wasOffline && self.isOnline && !self.pendingBakes.isEmpty {
                    await self.syncPending()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Local Storage

    private var storageURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("pending_bakes.json")
    }

    private func loadPending() {
        guard let data = try? Data(contentsOf: storageURL),
              let bakes = try? JSONDecoder().decode([PendingBake].self, from: data) else {
            return
        }
        pendingBakes = bakes
    }

    private func savePending() {
        guard let data = try? JSONEncoder().encode(pendingBakes) else { return }
        try? data.write(to: storageURL)
    }

    // MARK: - Queue & Sync

    func queueBake(payload: CreateBakePayload, imageDataItems: [Data]) {
        let pending = PendingBake(
            id: UUID().uuidString,
            payload: payload,
            imageDataItems: imageDataItems,
            createdLocally: .now
        )
        pendingBakes.append(pending)
        savePending()
    }

    func removePending(id: String) {
        pendingBakes.removeAll { $0.id == id }
        savePending()
    }

    func syncPending() async {
        guard !pendingBakes.isEmpty, !isSyncing else { return }
        isSyncing = true

        var remaining: [PendingBake] = []

        for pending in pendingBakes {
            do {
                let bake = try await APIClient.shared.createBake(pending.payload)
                for imageData in pending.imageDataItems {
                    _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: imageData)
                }
            } catch {
                // Keep it in the queue if sync fails
                remaining.append(pending)
            }
        }

        pendingBakes = remaining
        savePending()
        isSyncing = false
    }
}
