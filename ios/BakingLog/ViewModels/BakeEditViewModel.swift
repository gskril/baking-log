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

    // MARK: - Time Formatting

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    private static func parseTime(_ string: String) -> Date {
        // Try common formats
        let formats = ["h:mm a", "h:mma", "H:mm", "ha", "h a"]
        for format in formats {
            let f = DateFormatter()
            f.dateFormat = format
            if let date = f.date(from: string) {
                return date
            }
        }
        return .now
    }

    private static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    // MARK: - Load Existing

    func loadExisting(_ bake: Bake) {
        existingBakeId = bake.id
        pendingBakeId = nil
        title = bake.title
        notes = bake.notes ?? ""
        existingPhotos = bake.photos ?? []
        pendingExistingImages = []
        newImages = []
        ingredientEntries = []
        scheduleEntries = []
        error = nil

        // Parse bake_date
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        bakeDate = formatter.date(from: bake.bakeDate) ?? .now

        // Load structured ingredients if available, fall back to text
        if let structured = bake.ingredients, !structured.isEmpty {
            ingredientEntries = structured.map {
                let parsed = Self.parseAmount($0.amount)
                return EditableIngredient(name: $0.name, amountValue: parsed.value, unit: parsed.unit, note: $0.note ?? "")
            }
        } else if let text = bake.ingredientsText, !text.isEmpty {
            // Parse legacy text: each line becomes an ingredient with the full line as "name"
            ingredientEntries = text.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { EditableIngredient(name: $0, amountValue: "", unit: .grams, note: "") }
        }

        scheduleEntries = (bake.schedule ?? []).map {
            EditableScheduleEntry(timeDate: Self.parseTime($0.time), action: $0.action, note: $0.note ?? "")
        }
    }

    func loadExistingPending(_ pending: SyncManager.PendingBake) {
        existingBakeId = nil
        pendingBakeId = pending.id
        title = pending.payload.title
        notes = pending.payload.notes ?? ""
        existingPhotos = []
        newImages = []
        ingredientEntries = []
        scheduleEntries = []
        error = nil

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        bakeDate = formatter.date(from: pending.payload.bakeDate) ?? .now

        if let ingredients = pending.payload.ingredients, !ingredients.isEmpty {
            ingredientEntries = ingredients.map {
                let parsed = Self.parseAmount($0.amount)
                return EditableIngredient(name: $0.name, amountValue: parsed.value, unit: parsed.unit, note: $0.note ?? "")
            }
        } else if let text = pending.payload.ingredientsText, !text.isEmpty {
            ingredientEntries = text.components(separatedBy: "\n")
                .filter { !$0.isEmpty }
                .map { EditableIngredient(name: $0, amountValue: "", unit: .grams, note: "") }
        }

        if let schedule = pending.payload.schedule, !schedule.isEmpty {
            scheduleEntries = schedule.map {
                EditableScheduleEntry(timeDate: Self.parseTime($0.time), action: $0.action, note: $0.note ?? "")
            }
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
        scheduleEntries.append(EditableScheduleEntry(timeDate: .now, action: "", note: ""))
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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"

        let schedule = scheduleEntries
            .filter { !$0.action.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { ScheduleEntryPayload(time: Self.formatTime($0.timeDate), action: $0.action, note: $0.note.isEmpty ? nil : $0.note) }

        let ingredients = ingredientEntries
            .filter {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.amountValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .map {
                IngredientPayload(
                    name: $0.name,
                    amount: Self.formatAmount(value: $0.amountValue, unit: $0.unit),
                    note: $0.note.isEmpty ? nil : $0.note
                )
            }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = CreateBakePayload(
            title: title,
            bakeDate: formatter.string(from: bakeDate),
            ingredientsText: nil,
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
                ingredientsText: nil,
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
                    ingredientsText: nil,
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
                    Ingredient(id: "local-\(i)", bakeId: existingId, name: ing.name, amount: ing.amount, note: ing.note, sortOrder: i)
                }
                let scheduleModels = schedule.enumerated().map { i, entry in
                    ScheduleEntry(id: "local-\(i)", bakeId: existingId, time: entry.time, action: entry.action, note: entry.note, sortOrder: i)
                }

                return Bake(
                    id: existingId,
                    title: payload.title,
                    bakeDate: payload.bakeDate,
                    ingredientsText: nil,
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

    // MARK: - Ingredient Amount Helpers

    private static func parseAmount(_ rawAmount: String) -> (value: String, unit: IngredientUnit) {
        let trimmed = rawAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", .grams)
        }

        let lower = trimmed.lowercased()

        if let match = lower.range(of: #"^(\d+(?:\.\d+)?)\s*(g|gram|grams|tsp|tbsp|cup|cups)$"#, options: .regularExpression) {
            let matched = String(lower[match])
            let parts = matched.split(whereSeparator: \.isWhitespace)
            if parts.count == 1 {
                // Handles values like "90g" where unit is attached to the number.
                let attached = String(parts[0])
                if let numberRange = attached.range(of: #"^\d+(?:\.\d+)?"#, options: .regularExpression) {
                    let number = String(attached[numberRange])
                    let unitToken = attached.replacingOccurrences(of: #"^\d+(?:\.\d+)?"#, with: "", options: .regularExpression)
                    switch unitToken {
                    case "tsp": return (number, .tsp)
                    case "tbsp": return (number, .tbsp)
                    case "cup", "cups": return (number, .cup)
                    default: return (number, .grams)
                    }
                }
            } else if parts.count == 2 {
                let number = String(parts[0])
                let unitToken = String(parts[1])
                switch unitToken {
                case "tsp": return (number, .tsp)
                case "tbsp": return (number, .tbsp)
                case "cup", "cups": return (number, .cup)
                default: return (number, .grams)
                }
            }
        }

        if lower.range(of: #"^\d+(?:\.\d+)?$"#, options: .regularExpression) != nil {
            return (trimmed, .grams)
        }

        // Unknown format: preserve text and default unit to grams.
        return (trimmed, .grams)
    }

    private static func formatAmount(value rawValue: String, unit: IngredientUnit) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return "\(value) \(unit.rawValue)"
    }
}
