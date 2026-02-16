import Foundation
import SwiftUI

@MainActor
class BakeEditViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var bakeDate: Date = .now
    @Published var ingredients: String = ""
    @Published var notes: String = ""
    @Published var scheduleEntries: [EditableScheduleEntry] = []
    @Published var existingPhotos: [Photo] = []
    @Published var newImages: [UIImage] = []
    @Published var isSaving = false
    @Published var error: String?
    @Published var savedOffline = false

    private var existingBakeId: String?

    struct EditableScheduleEntry: Identifiable {
        let id = UUID()
        var time: String
        var action: String
        var note: String
    }

    var isEditing: Bool { existingBakeId != nil }

    func loadExisting(_ bake: Bake) {
        existingBakeId = bake.id
        title = bake.title
        ingredients = bake.ingredients ?? ""
        notes = bake.notes ?? ""
        existingPhotos = bake.photos ?? []

        // Parse bake_date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        bakeDate = formatter.date(from: bake.bakeDate) ?? .now

        scheduleEntries = (bake.schedule ?? []).map {
            EditableScheduleEntry(time: $0.time, action: $0.action, note: $0.note ?? "")
        }
    }

    func addScheduleEntry() {
        scheduleEntries.append(EditableScheduleEntry(time: "", action: "", note: ""))
    }

    func removeScheduleEntry(at offsets: IndexSet) {
        scheduleEntries.remove(atOffsets: offsets)
    }

    func moveScheduleEntry(from source: IndexSet, to destination: Int) {
        scheduleEntries.move(fromOffsets: source, toOffset: destination)
    }

    func save() async -> Bake? {
        isSaving = true
        error = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let schedule = scheduleEntries
            .filter { !$0.time.isEmpty || !$0.action.isEmpty }
            .map { ScheduleEntryPayload(time: $0.time, action: $0.action, note: $0.note.isEmpty ? nil : $0.note) }

        let payload = CreateBakePayload(
            title: title,
            bakeDate: formatter.string(from: bakeDate),
            ingredients: ingredients.isEmpty ? nil : ingredients,
            notes: notes.isEmpty ? nil : notes,
            schedule: schedule.isEmpty ? nil : schedule
        )

        // Convert images to Data on @MainActor (UIImage is not Sendable)
        let imageDataItems = newImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

        do {
            let bake: Bake
            if let existingId = existingBakeId {
                bake = try await APIClient.shared.updateBake(id: existingId, payload)
            } else {
                bake = try await APIClient.shared.createBake(payload)
            }

            for data in imageDataItems {
                _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: data)
            }

            isSaving = false
            return bake
        } catch {
            // If creating a new bake and offline, queue it locally
            if existingBakeId == nil {
                SyncManager.shared.queueBake(payload: payload, imageDataItems: imageDataItems)
                savedOffline = true
                isSaving = false
                // Return a placeholder so the UI dismisses
                return Bake(
                    id: "pending",
                    title: payload.title,
                    bakeDate: payload.bakeDate,
                    ingredients: payload.ingredients,
                    notes: payload.notes,
                    schedule: nil,
                    photos: nil,
                    createdAt: Date.now.ISO8601Format(),
                    updatedAt: Date.now.ISO8601Format()
                )
            }
            self.error = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    func deleteExistingPhoto(_ photo: Photo) async {
        try? await APIClient.shared.deletePhoto(id: photo.id)
        existingPhotos.removeAll { $0.id == photo.id }
    }
}
