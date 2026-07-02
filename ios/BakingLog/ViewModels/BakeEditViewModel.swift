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
    @Published var newImages: [UIImage] = []
    @Published var isSaving = false
    @Published var error: String?

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
        newImages = []
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

        do {
            let bake: Bake
            if let existingId = existingBakeId {
                bake = try await APIClient.shared.updateBake(id: existingId, payload)
            } else {
                bake = try await APIClient.shared.createBake(payload)
            }

            for data in newImageData {
                _ = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: data)
            }

            isSaving = false
            return bake
        } catch {
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
