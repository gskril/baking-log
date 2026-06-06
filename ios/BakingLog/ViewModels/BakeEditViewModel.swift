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
        title = bake.title ?? ""
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

        // Load structured ingredients
        if let structured = bake.ingredients, !structured.isEmpty {
            ingredientEntries = structured.map {
                let parsed = Self.parseAmount($0.amount)
                return EditableIngredient(name: $0.name, amountValue: parsed.value, unit: parsed.unit, note: $0.note ?? "")
            }
        }

        scheduleEntries = (bake.schedule ?? []).map {
            EditableScheduleEntry(timeDate: Self.parseTime($0.time), action: $0.action, note: $0.note ?? "")
        }
    }

    func loadExistingPending(_ pending: SyncManager.PendingBake) {
        existingBakeId = nil
        pendingBakeId = pending.id
        title = pending.payload.title ?? ""
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

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload = CreateBakePayload(
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            bakeDate: formatter.string(from: bakeDate),

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
                    Ingredient(id: "local-\(i)", bakeId: existingId, name: ing.name, amount: ing.amount, note: ing.note, sortOrder: i)
                }
                let scheduleModels = schedule.enumerated().map { i, entry in
                    ScheduleEntry(id: "local-\(i)", bakeId: existingId, time: entry.time, action: entry.action, note: entry.note, sortOrder: i)
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

    // MARK: - Ingredient Amount Helpers

    /// Matches a unit token (including spelled-out and plural variants) to a
    /// known `IngredientUnit`. Returns nil for unrecognized tokens.
    private static func ingredientUnit(from token: String) -> IngredientUnit? {
        switch token {
        case "g", "gram", "grams": return .grams
        case "tsp", "teaspoon", "teaspoons": return .tsp
        case "tbsp", "tablespoon", "tablespoons": return .tbsp
        case "cup", "cups": return .cup
        default: return nil
        }
    }

    private static func parseAmount(_ rawAmount: String) -> (value: String, unit: IngredientUnit) {
        let trimmed = rawAmount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ("", .grams)
        }

        let lower = trimmed.lowercased()

        // Pull off a leading number. The decimal portion is optional and a
        // leading zero is not required, so ".5", "0.5", "4" and "1.67" all match.
        if let numberRange = lower.range(of: #"^\d*\.?\d+"#, options: .regularExpression) {
            let number = String(lower[numberRange])

            // Whatever follows the number is the unit. Take the first token so
            // attached units ("90g"), spaced units ("4 cup") and even already
            // corrupted values (".5 cup g") all resolve to a single unit.
            let unitToken = lower[numberRange.upperBound...]
                .split(whereSeparator: \.isWhitespace)
                .first
                .map(String.init) ?? ""

            if unitToken.isEmpty {
                return (number, .grams)
            }
            if let unit = ingredientUnit(from: unitToken) {
                return (number, unit)
            }
        }

        // Unknown format: preserve the original text. formatAmount will not
        // append a unit to it, so it round-trips unchanged.
        return (trimmed, .grams)
    }

    private static func formatAmount(value rawValue: String, unit: IngredientUnit) -> String {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        // Only append the unit to a bare number. If the value already contains
        // non-numeric text (an amount we couldn't fully parse), leave it as-is
        // so we never produce strings like ".5 cup g".
        guard value.range(of: #"^\d*\.?\d+$"#, options: .regularExpression) != nil else {
            return value
        }
        return "\(value) \(unit.rawValue)"
    }
}
