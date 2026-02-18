import Foundation
import Network

@MainActor
class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var isOnline = true
    @Published var pendingBakes: [PendingBake] = []
    @Published var pendingUpdates: [PendingUpdate] = []
    @Published var pendingPhotoUploads: [PendingPhotoUpload] = []
    @Published var isSyncing = false

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.bakinglog.networkmonitor")

    struct PendingBake: Identifiable, Codable {
        let id: String
        var payload: CreateBakePayload
        var imageDataItems: [Data]
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

    struct PendingUpdate: Identifiable, Codable {
        let id: String
        let bakeId: String
        var payload: CreateBakePayload
        let queuedAt: Date
    }

    struct PendingPhotoUpload: Identifiable, Codable {
        let id: String
        let bakeId: String
        var imageDataItems: [Data]
        let queuedAt: Date
    }

    var hasAnyPending: Bool {
        !pendingBakes.isEmpty || !pendingUpdates.isEmpty || !pendingPhotoUploads.isEmpty
    }

    private init() {
        loadPending()
        loadPendingUpdates()
        loadPendingPhotoUploads()
        startMonitoring()
    }

    // MARK: - Network Monitoring

    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isOnline = path.status == .satisfied
                if self.isOnline && self.hasAnyPending {
                    await self.syncPending()
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }

    // MARK: - Storage URLs

    private var documentsDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var pendingBakesURL: URL {
        documentsDir.appendingPathComponent("pending_bakes.json")
    }

    private var pendingUpdatesURL: URL {
        documentsDir.appendingPathComponent("pending_updates.json")
    }

    private var pendingPhotoUploadsURL: URL {
        documentsDir.appendingPathComponent("pending_photo_uploads.json")
    }

    // MARK: - Load/Save: Pending Bakes

    private func loadPending() {
        guard let data = try? Data(contentsOf: pendingBakesURL),
              let bakes = try? JSONDecoder().decode([PendingBake].self, from: data) else {
            return
        }
        pendingBakes = bakes
    }

    private func savePending() {
        guard let data = try? JSONEncoder().encode(pendingBakes) else { return }
        try? data.write(to: pendingBakesURL)
    }

    // MARK: - Load/Save: Pending Updates

    private func loadPendingUpdates() {
        guard let data = try? Data(contentsOf: pendingUpdatesURL),
              let updates = try? JSONDecoder().decode([PendingUpdate].self, from: data) else {
            return
        }
        pendingUpdates = updates
    }

    private func savePendingUpdates() {
        guard let data = try? JSONEncoder().encode(pendingUpdates) else { return }
        try? data.write(to: pendingUpdatesURL)
    }

    // MARK: - Load/Save: Pending Photo Uploads

    private func loadPendingPhotoUploads() {
        guard let data = try? Data(contentsOf: pendingPhotoUploadsURL),
              let uploads = try? JSONDecoder().decode([PendingPhotoUpload].self, from: data) else {
            return
        }
        pendingPhotoUploads = uploads
    }

    private func savePendingPhotoUploads() {
        guard let data = try? JSONEncoder().encode(pendingPhotoUploads) else { return }
        try? data.write(to: pendingPhotoUploadsURL)
    }

    // MARK: - Queue: Bakes (create)

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

    func updatePending(id: String, payload: CreateBakePayload, imageDataItems: [Data]) {
        guard let index = pendingBakes.firstIndex(where: { $0.id == id }) else { return }
        pendingBakes[index].payload = payload
        pendingBakes[index].imageDataItems = imageDataItems
        savePending()
    }

    // MARK: - Queue: Updates (edit existing bake)

    func queueUpdate(bakeId: String, payload: CreateBakePayload) {
        // Coalesce: replace existing payload for the same bakeId
        if let index = pendingUpdates.firstIndex(where: { $0.bakeId == bakeId }) {
            pendingUpdates[index].payload = payload
        } else {
            pendingUpdates.append(PendingUpdate(
                id: UUID().uuidString,
                bakeId: bakeId,
                payload: payload,
                queuedAt: .now
            ))
        }
        savePendingUpdates()
    }

    func clearPendingUpdate(for bakeId: String) {
        pendingUpdates.removeAll { $0.bakeId == bakeId }
        savePendingUpdates()
    }

    // MARK: - Queue: Photo Uploads

    func queuePhotoUpload(bakeId: String, imageDataItems: [Data]) {
        // Coalesce: append images to existing entry for the same bakeId
        if let index = pendingPhotoUploads.firstIndex(where: { $0.bakeId == bakeId }) {
            pendingPhotoUploads[index].imageDataItems.append(contentsOf: imageDataItems)
        } else {
            pendingPhotoUploads.append(PendingPhotoUpload(
                id: UUID().uuidString,
                bakeId: bakeId,
                imageDataItems: imageDataItems,
                queuedAt: .now
            ))
        }
        savePendingPhotoUploads()
    }

    // MARK: - Query

    func hasPendingChanges(for bakeId: String) -> Bool {
        pendingUpdates.contains { $0.bakeId == bakeId }
            || pendingPhotoUploads.contains { $0.bakeId == bakeId }
    }

    func mergedBakeWithPendingChanges(_ bake: Bake) -> Bake {
        guard let pendingUpdate = pendingUpdates.first(where: { $0.bakeId == bake.id }) else {
            return bake
        }

        return bakeFromPayload(
            id: bake.id,
            payload: pendingUpdate.payload,
            createdAt: bake.createdAt,
            updatedAt: pendingUpdate.queuedAt.ISO8601Format(),
            photos: bake.photos
        )
    }

    func localBakeFromPendingUpdate(bakeId: String) -> Bake? {
        guard let pendingUpdate = pendingUpdates.first(where: { $0.bakeId == bakeId }) else {
            return nil
        }

        return bakeFromPayload(
            id: bakeId,
            payload: pendingUpdate.payload,
            createdAt: pendingUpdate.queuedAt.ISO8601Format(),
            updatedAt: pendingUpdate.queuedAt.ISO8601Format(),
            photos: nil
        )
    }

    private func bakeFromPayload(
        id: String,
        payload: CreateBakePayload,
        createdAt: String,
        updatedAt: String,
        photos: [Photo]?
    ) -> Bake {
        let ingredientModels = payload.ingredients?.enumerated().map { index, ingredient in
            Ingredient(
                id: "pending-\(index)",
                bakeId: id,
                name: ingredient.name,
                amount: ingredient.amount,
                note: ingredient.note,
                sortOrder: index
            )
        }

        let scheduleModels = payload.schedule?.enumerated().map { index, step in
            ScheduleEntry(
                id: "pending-\(index)",
                bakeId: id,
                time: step.time,
                action: step.action,
                note: step.note,
                sortOrder: index
            )
        }

        return Bake(
            id: id,
            title: payload.title,
            bakeDate: payload.bakeDate,
            ingredientsText: payload.ingredientsText,
            ingredients: ingredientModels,
            ingredientCount: ingredientModels?.count,
            notes: payload.notes,
            schedule: scheduleModels,
            photos: photos,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    // MARK: - Sync All Queues

    func syncPending() async {
        guard hasAnyPending, !isSyncing else { return }
        isSyncing = true

        // 1. Sync pending creates
        var remainingBakes: [PendingBake] = []
        for pending in pendingBakes {
            do {
                let bake = try await APIClient.shared.createBake(pending.payload)
                for imageData in pending.imageDataItems {
                    _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: imageData)
                }
            } catch {
                remainingBakes.append(pending)
            }
        }
        pendingBakes = remainingBakes
        savePending()

        // 2. Sync pending updates
        var remainingUpdates: [PendingUpdate] = []
        for update in pendingUpdates {
            do {
                _ = try await APIClient.shared.updateBake(id: update.bakeId, update.payload)
            } catch {
                remainingUpdates.append(update)
            }
        }
        pendingUpdates = remainingUpdates
        savePendingUpdates()

        // 3. Sync pending photo uploads
        var remainingPhotos: [PendingPhotoUpload] = []
        for upload in pendingPhotoUploads {
            var failedData: [Data] = []
            for imageData in upload.imageDataItems {
                do {
                    _ = try await APIClient.shared.uploadPhoto(bakeId: upload.bakeId, imageData: imageData)
                } catch {
                    failedData.append(imageData)
                }
            }
            if !failedData.isEmpty {
                var remaining = upload
                remaining.imageDataItems = failedData
                remainingPhotos.append(remaining)
            }
        }
        pendingPhotoUploads = remainingPhotos
        savePendingPhotoUploads()

        isSyncing = false
    }
}
