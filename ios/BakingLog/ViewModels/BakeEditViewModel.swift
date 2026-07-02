import Foundation
import PhotosUI
import SwiftUI

@Observable @MainActor
final class BakeEditViewModel {
    var title: String = ""
    var bakeDate: Date = .now
    var ingredientEntries: [EditableIngredient] = []
    var notes: String = ""
    var scheduleEntries: [EditableScheduleEntry] = []
    var existingPhotos: [Photo] = []
    var pendingPhotos: [PendingPhoto] = []
    var isSaving = false
    var error: String?

    private var existingBakeId: String?

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

    /// A picked photo that hasn't been uploaded yet. `jpegData` is already
    /// downsampled and JPEG-encoded at pick time (see `addPhotos`), so
    /// `save()` uploads it as-is; `thumbnail` is decoded from that same small
    /// JPEG purely for display in the edit sheet.
    struct PendingPhoto: Identifiable {
        let id = UUID()
        let jpegData: Data
        let thumbnail: UIImage
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

    var isEditing: Bool { existingBakeId != nil }

    // MARK: - Load Existing

    func loadExisting(_ bake: Bake) {
        existingBakeId = bake.id
        title = bake.title ?? ""
        notes = bake.notes ?? ""
        existingPhotos = bake.photos ?? []
        pendingPhotos = []
        error = nil

        bakeDate = Formatters.isoDay.date(from: bake.bakeDate) ?? .now
        ingredientEntries = Self.editableIngredients(from: bake.ingredients)
        scheduleEntries = (bake.schedule ?? []).map {
            EditableScheduleEntry(timeDate: $0.date ?? .now, action: $0.action, note: $0.note ?? "")
        }
    }

    func loadPrefill(_ prefill: Prefill) {
        existingBakeId = nil
        title = prefill.title
        notes = prefill.notes ?? ""
        ingredientEntries = prefill.ingredientEntries
        scheduleEntries = []
        existingPhotos = []
        pendingPhotos = []
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

    // MARK: - Photos

    /// Loads picked photos and downsamples/JPEG-encodes them immediately, off
    /// the main actor, so `save()` only ever uploads already-processed `Data`
    /// and no full-resolution `UIImage` is ever retained.
    func addPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }

        var failureCount = 0
        var lastError: Error?

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failureCount += 1
                    continue
                }
                let jpegData = try await ImageProcessing.downsampledJPEGData(from: data)
                guard let thumbnail = UIImage(data: jpegData) else {
                    failureCount += 1
                    continue
                }
                pendingPhotos.append(PendingPhoto(jpegData: jpegData, thumbnail: thumbnail))
            } catch {
                failureCount += 1
                lastError = error
            }
        }

        if failureCount > 0 {
            let failureText = failureCount == 1 ? "1 photo failed to load." : "\(failureCount) photos failed to load."
            if let lastError {
                error = "\(failureText) \(lastError.localizedDescription)"
            } else {
                error = failureText
            }
        }
    }

    func removePendingPhoto(id: UUID) {
        pendingPhotos.removeAll { $0.id == id }
    }

    // MARK: - Save

    func save() async -> Bake? {
        isSaving = true
        error = nil

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

        // Photos were downsampled and JPEG-encoded at pick time; snapshot the
        // list because it shrinks as uploads succeed.
        let uploads = pendingPhotos

        do {
            let bake: Bake
            if let existingId = existingBakeId {
                bake = try await APIClient.shared.updateBake(id: existingId, payload)
            } else {
                bake = try await APIClient.shared.createBake(payload)
                // The bake now exists server-side; a retry after a photo
                // failure must update it, not create a duplicate.
                existingBakeId = bake.id
            }

            var failedCount = 0
            var lastUploadError: Error?
            for photo in uploads {
                do {
                    _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: photo.jpegData)
                    // Only photos that haven't uploaded yet are retried.
                    pendingPhotos.removeAll { $0.id == photo.id }
                } catch {
                    failedCount += 1
                    lastUploadError = error
                }
            }

            isSaving = false

            if failedCount > 0, let lastUploadError {
                let noun = failedCount == 1 ? "1 photo" : "\(failedCount) photos"
                error = "Bake saved, but \(noun) failed to upload. \(lastUploadError.localizedDescription)"
                return nil
            }

            return bake
        } catch {
            self.error = error.localizedDescription
            isSaving = false
            return nil
        }
    }

    func deleteExistingPhoto(_ photo: Photo) async {
        do {
            try await APIClient.shared.deletePhoto(id: photo.id)
            existingPhotos.removeAll { $0.id == photo.id }
        } catch {
            self.error = "Couldn't delete photo. \(error.localizedDescription)"
        }
    }
}
