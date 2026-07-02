import Foundation
import PhotosUI
import SwiftUI

@MainActor
final class BakeDetailViewModel: ObservableObject {
    @Published var bake: Bake?
    @Published var isLoading = true
    @Published var loadError: String?
    @Published var actionError: String?
    @Published var editedNotes: String = ""
    @Published var isSavingNotes = false
    @Published var isSavingStep = false
    @Published var isUploadingPhotos = false
    @Published var newStepTime: Date = .now
    @Published var newStepAction: String = ""
    @Published var newStepNote: String = ""

    private let bakeId: String

    init(bakeId: String) {
        self.bakeId = bakeId
    }

    // MARK: - Load

    func load() async {
        if bake == nil {
            isLoading = true
        }
        loadError = nil

        do {
            let loaded = try await APIClient.shared.getBake(id: bakeId)
            bake = loaded
            editedNotes = loaded.notes ?? ""
        } catch {
            if bake == nil {
                loadError = error.localizedDescription
            } else {
                // The full-screen error only renders with no bake loaded; a
                // failed refresh must surface through the alert instead of
                // silently showing stale data.
                actionError = "Couldn't refresh. \(error.localizedDescription)"
            }
        }
        isLoading = false
    }

    // MARK: - Schedule

    func saveNewStep() async -> Bool {
        guard let bake else { return false }
        isSavingStep = true
        defer { isSavingStep = false }

        let trimmedAction = newStepAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = newStepNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAction.isEmpty else { return false }

        // Build schedule: existing entries + new entry
        var schedulePayload = (bake.schedule ?? []).map {
            ScheduleEntryPayload(occursAt: $0.occursAt, action: $0.action, note: $0.note)
        }
        let newEntry = ScheduleEntryPayload(
            occursAt: Formatters.isoDateTime.string(from: newStepTime),
            action: trimmedAction,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        schedulePayload.append(newEntry)

        let payload = buildPayload(
            from: bake,
            notes: bake.notes,
            schedule: schedulePayload
        )

        do {
            let updated = try await APIClient.shared.updateBake(id: bake.id, payload)
            self.bake = updated
            editedNotes = updated.notes ?? ""
            resetAddStep()
            return true
        } catch {
            actionError = error.localizedDescription
            return false
        }
    }

    func resetAddStep() {
        newStepTime = .now
        newStepAction = ""
        newStepNote = ""
    }

    // MARK: - Notes

    func saveNotes() async {
        guard let bake else { return }
        isSavingNotes = true
        defer { isSavingNotes = false }

        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmed.isEmpty ? nil : trimmed
        let existingSchedule = (bake.schedule ?? []).map {
            ScheduleEntryPayload(occursAt: $0.occursAt, action: $0.action, note: $0.note)
        }

        let payload = buildPayload(
            from: bake,
            notes: noteValue,
            schedule: existingSchedule.isEmpty ? nil : existingSchedule
        )

        do {
            let updated = try await APIClient.shared.updateBake(id: bake.id, payload)
            self.bake = updated
            editedNotes = updated.notes ?? ""
        } catch {
            actionError = error.localizedDescription
        }
    }

    // MARK: - Photos

    func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        guard let bake else { return }

        isUploadingPhotos = true

        var updatedBake = bake
        var failureCount = 0
        var lastError: Error?

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failureCount += 1
                    continue
                }
                // Downsample + re-encode as JPEG off the main actor so the
                // upload is small enough for the 15s request timeout and the
                // stored bytes actually match APIClient's image/jpeg label.
                let jpegData = try await ImageProcessing.downsampledJPEGData(from: data)
                let photo = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: jpegData)

                var photos = updatedBake.photos ?? []
                photos.append(photo)
                updatedBake.photos = photos
            } catch {
                failureCount += 1
                lastError = error
            }
        }

        self.bake = updatedBake

        if failureCount > 0 {
            let failureText = failureCount == 1 ? "1 photo failed to upload." : "\(failureCount) photos failed to upload."
            if let lastError {
                actionError = "\(failureText) \(lastError.localizedDescription)"
            } else {
                actionError = failureText
            }
        }

        isUploadingPhotos = false
    }

    // MARK: - Payload

    private func buildPayload(from bake: Bake, notes: String?, schedule: [ScheduleEntryPayload]?) -> CreateBakePayload {
        let ingredientsPayload = bake.ingredients?.map {
            IngredientPayload(name: $0.name, amountValue: $0.amountValue, unit: $0.unit, note: $0.note)
        }

        return CreateBakePayload(
            title: bake.title,
            bakeDate: bake.bakeDate,

            ingredients: ingredientsPayload,
            notes: notes,
            schedule: schedule
        )
    }
}
