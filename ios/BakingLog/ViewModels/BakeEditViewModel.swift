import Foundation
import SwiftUI

@MainActor
class BakeEditViewModel: ObservableObject {
    @Published var title: String = ""
    @Published var bakeDate: Date = .now
    @Published var ingredientEntries: [EditableIngredient] = []
    @Published var notes: String = ""
    @Published var scheduleEntries: [EditableScheduleEntry] = []
    @Published var existingPhotos: [Photo] = []
    @Published var pendingExistingImages: [Data] = []
    @Published var newImages: [UIImage] = []
    @Published var isSaving = false
    @Published var error: String?
    @Published var savedOffline = false

    private var existingBakeId: String?
    private var pendingBakeId: String?

    enum IngredientUnit: String, CaseIterable, Identifiable {
        case grams = "g"
        case tsp = "tsp"
        case tbsp = "tbsp"
        case cup = "cup"

        var id: String { rawValue }
    }

    struct EditableIngredient: Identifiable {
        let id = UUID()
        var name: String
        var amountValue: String
        var unit: IngredientUnit
        var note: String
    }

    struct EditableScheduleEntry: Identifiable {
        let id = UUID()
        var timeDate: Date
        var action: String
        var note: String
    }

    struct Prefill {
        var title: String
        var ingredientEntries: [EditableIngredient]
        var notes: String?
    }

    var isEditing: Bool { existingBakeId != nil || pendingBakeId != nil }

    // MARK: - Load Existing

    func loadExisting(_ bake: Bake) {
        existingBakeId = bake.id
        pendingBakeId = nil
        title = bake.title ?? ""
        notes = bake.notes ?? ""
        existingPhotos = bake.photos ?? []
        pendingExistingImages = []
        newImages = []
        error = nil

        bakeDate = Formatters.isoDay.date(from: bake.bakeDate) ?? .now
        ingredientEntries = Self.editableIngredients(from: bake.ingredients)
        scheduleEntries = (bake.schedule ?? []).map {
            EditableScheduleEntry(timeDate: $0.date ?? .now, action: $0.action, note: $0.note ?? "")
        }
    }

    func loadExistingPending(_ pending: SyncManager.PendingBake) {
        existingBakeId = nil
        pendingBakeId = pending.id
        title = pending.payload.title ?? ""
        notes = pending.payload.notes ?? ""
        existingPhotos = []
        newImages = []
        error = nil

        bakeDate = Formatters.isoDay.date(from: pending.payload.bakeDate) ?? .now

        ingredientEntries = (pending.payload.ingredients ?? []).map {
            EditableIngredient(
                name: $0.name,
                amountValue: $0.amountValue.map(Formatters.amountString) ?? "",
                unit: $0.unit.flatMap(IngredientUnit.init(rawValue:)) ?? .grams,
                note: $0.note ?? ""
            )
        }

        scheduleEntries = (pending.payload.schedule ?? []).map {
            EditableScheduleEntry(timeDate: $0.date ?? .now, action: $0.action, note: $0.note ?? "")
        }

        pendingExistingImages = pending.imageDataItems
    }

    func loadPrefill(_ prefill: Prefill) {
        existingBakeId = nil
        pendingBakeId = nil
        title = prefill.title
        notes = prefill.notes ?? ""
        ingredientEntries = prefill.ingredientEntries
        scheduleEntries = []
        existingPhotos = []
        pendingExistingImages = []
        newImages = []
        error = nil
        bakeDate = .now
    }

    private static func editableIngredients(from ingredients: [Ingredient]?) -> [EditableIngredient] {
        (ingredients ?? []).map {
            EditableIngredient(
                name: $0.name,
                amountValue: $0.amountValue.map(Formatters.amountString) ?? "",
                unit: $0.unit.flatMap(IngredientUnit.init(rawValue:)) ?? .grams,
                note: $0.note ?? ""
            )
        }
    }

    // MARK: - Ingredient CRUD

    func addIngredient() {
        ingredientEntries.append(EditableIngredient(name: "", amountValue: "", unit: .grams, note: ""))
    }

    func removeIngredient(at offsets: IndexSet) {
        ingredientEntries.remove(atOffsets: offsets)
    }

    func moveIngredient(from source: IndexSet, to destination: Int) {
        ingredientEntries.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Schedule CRUD

    func addScheduleEntry() {
        // Default to the last entry's time so consecutive steps land on the same day.
        let defaultTime = scheduleEntries.last?.timeDate ?? .now
        scheduleEntries.append(EditableScheduleEntry(timeDate: defaultTime, action: "", note: ""))
    }

    func removeScheduleEntry(at offsets: IndexSet) {
        scheduleEntries.remove(atOffsets: offsets)
    }

    func moveScheduleEntry(from source: IndexSet, to destination: Int) {
        scheduleEntries.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Save

    func save() async -> Bake? {
        isSaving = true
        error = nil
        savedOffline = false

        let schedule = scheduleEntries
            .filter { !$0.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map {
                ScheduleEntryPayload(
                    occursAt: Formatters.isoDateTime.string(from: $0.timeDate),
                    action: $0.action,
                    note: $0.note.isEmpty ? nil : $0.note
                )
            }

        let ingredients = ingredientEntries
            .filter {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.amountValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map { entry in
                let value = Double(entry.amountValue.trimmingCharacters(in: .whitespacesAndNewlines))
                return IngredientPayload(
                    name: entry.name,
                    amountValue: value,
                    unit: value == nil ? nil : entry.unit.rawValue,
                    note: entry.note.isEmpty ? nil : entry.note
                )
            }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = CreateBakePayload(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            bakeDate: Formatters.isoDay.string(from: bakeDate),

            ingredients: ingredients.isEmpty ? nil : ingredients,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            schedule: schedule.isEmpty ? nil : schedule
        )

        // Convert images to Data on @MainActor (UIImage is not Sendable)
        let newImageData = newImages.compactMap { $0.jpegData(compressionQuality: 0.8) }

        // If editing a pending bake, update locally — no API call
        if let pendingId = pendingBakeId {
            let allImageData = pendingExistingImages + newImageData
            SyncManager.shared.updatePending(id: pendingId, payload: payload, imageDataItems: allImageData)
            isSaving = false
            return Bake(
                id: "pending",
                title: payload.title,
                bakeDate: payload.bakeDate,

                ingredients: nil,
                ingredientCount: nil,
                notes: payload.notes,
                schedule: nil,
                photos: nil,
                createdAt: Date.now.ISO8601Format(),
                updatedAt: Date.now.ISO8601Format()
            )
        }

        do {
            let bake: Bake
            if let existingId = existingBakeId {
                bake = try await APIClient.shared.updateBake(id: existingId, payload)
                SyncManager.shared.clearPendingUpdate(for: existingId)
            } else {
                bake = try await APIClient.shared.createBake(payload)
            }

            var failedImageData: [Data] = []
            for data in newImageData {
                do {
                    _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: data)
                } catch {
                    failedImageData.append(data)
                }
            }

            if !failedImageData.isEmpty {
                SyncManager.shared.queuePhotoUpload(bakeId: bake.id, imageDataItems: failedImageData)
                savedOffline = true
            }

            isSaving = false
            return bake
        } catch {
            if existingBakeId == nil {
                // Creating a new bake offline — queue it
                SyncManager.shared.queueBake(payload: payload, imageDataItems: newImageData)
                savedOffline = true
                isSaving = false
                return Bake(
                    id: "pending",
                    title: payload.title,
                    bakeDate: payload.bakeDate,

                    ingredients: nil,
                    ingredientCount: nil,
                    notes: payload.notes,
                    schedule: nil,
                    photos: nil,
                    createdAt: Date.now.ISO8601Format(),
                    updatedAt: Date.now.ISO8601Format()
                )
            } else if let existingId = existingBakeId {
                // Updating an existing bake offline — queue update + photos
                SyncManager.shared.queueUpdate(bakeId: existingId, payload: payload)
                if !newImageData.isEmpty {
                    SyncManager.shared.queuePhotoUpload(bakeId: existingId, imageDataItems: newImageData)
                }
                savedOffline = true
                isSaving = false

                let ingredientModels = ingredients.enumerated().map { i, ing in
                    Ingredient(id: "local-\(i)", bakeId: existingId, name: ing.name, amountValue: ing.amountValue, unit: ing.unit, note: ing.note, sortOrder: i)
                }
                let scheduleModels = schedule.enumerated().map { i, entry in
                    ScheduleEntry(id: "local-\(i)", bakeId: existingId, occursAt: entry.occursAt, action: entry.action, note: entry.note, sortOrder: i)
                }

                return Bake(
                    id: existingId,
                    title: payload.title,
                    bakeDate: payload.bakeDate,

                    ingredients: ingredientModels.isEmpty ? nil : ingredientModels,
                    ingredientCount: ingredientModels.isEmpty ? nil : ingredientModels.count,
                    notes: payload.notes,
                    schedule: scheduleModels.isEmpty ? nil : scheduleModels,
                    photos: existingPhotos.isEmpty ? nil : existingPhotos,
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
