import SwiftUI
import PhotosUI

struct PendingBakeDetailView: View {
    let pendingId: String
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var showingEdit = false
    @State private var showingAddStep = false
    @State private var newStepTime: Date = .now
    @State private var newStepAction: String = ""
    @State private var newStepNote: String = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isAddingPhotos = false
    @State private var editedNotes: String = ""
    @FocusState private var isNewStepActionFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var pending: SyncManager.PendingBake? {
        syncManager.pendingBakes.first { $0.id == pendingId }
    }

    var body: some View {
        Group {
            if let pending {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Photos
                        photosSection(pending)

                        // Ingredients
                        ingredientsSection(pending.payload)

                        // Schedule
                        scheduleSection(pending)

                        // Notes
                        notesSection(pending)
                    }
                    .padding()
                }
            } else {
                ContentUnavailableView {
                    Label("Bake Synced", systemImage: "checkmark.circle")
                } description: {
                    Text("This bake has been synced to the server.")
                } actions: {
                    Button("Back") { dismiss() }
                }
            }
        }
        .navigationTitle(pending?.payload.title ?? "Pending Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if pending != nil {
                Button("Edit") {
                    showingEdit = true
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let pending {
                BakeEditView(existingPending: pending) {
                    showingEdit = false
                }
            }
        }
        .onAppear {
            editedNotes = pending?.payload.notes ?? ""
        }
        .onChange(of: pending?.payload.notes ?? "") { _, newValue in
            editedNotes = newValue
        }
        .onChange(of: selectedPhotos) {
            Task { await addSelectedPhotosToPending() }
        }
    }

    // MARK: - Photos

    @ViewBuilder
    private func photosSection(_ pending: SyncManager.PendingBake) -> some View {
        SectionBlock(title: "Photos") {
            if !pending.imageDataItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(pending.imageDataItems.indices, id: \.self) { i in
                            if let uiImage = UIImage(data: pending.imageDataItems[i]) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 280, height: 210)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                }
                .padding(.horizontal, 1)
            } else {
                Text("No photos yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            PhotosPicker(
                selection: $selectedPhotos,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add Photos", systemImage: "photo.on.rectangle.angled")
            }
            .disabled(isAddingPhotos)

            if isAddingPhotos {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Adding photos...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private func ingredientsSection(_ payload: CreateBakePayload) -> some View {
        if let ingredients = payload.ingredients, !ingredients.isEmpty {
            SectionBlock(title: "Ingredients") {
                ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                    HStack(alignment: .top) {
                        Text(ingredient.name)
                            .font(.body)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(ingredient.amount)
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                            if let note = ingredient.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Schedule Section

    @ViewBuilder
    private func scheduleSection(_ pending: SyncManager.PendingBake) -> some View {
        SectionBlock(title: "Schedule") {
            if let schedule = pending.payload.schedule, !schedule.isEmpty {
                ForEach(Array(schedule.enumerated()), id: \.offset) { _, entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.time)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.action)
                                .font(.body)
                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }

            if showingAddStep {
                inlineAddStepForm()
            } else {
                Button {
                    showingAddStep = true
                    DispatchQueue.main.async {
                        isNewStepActionFocused = true
                    }
                } label: {
                    Label("Add Step", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private func notesSection(_ pending: SyncManager.PendingBake) -> some View {
        let currentNotes = pending.payload.notes ?? ""
        let notesChanged = editedNotes != currentNotes

        SectionBlock(title: "Notes") {
            TextEditor(text: $editedNotes)
                .frame(minHeight: 100)
                .padding(4)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }

            HStack {
                Button("Reset") {
                    editedNotes = currentNotes
                }
                .foregroundStyle(.secondary)
                .disabled(!notesChanged)

                Spacer()

                Button("Save Notes") {
                    saveNotesToPending()
                }
                .bold()
                .disabled(!notesChanged)
            }
        }
    }

    // MARK: - Inline Add Step

    @ViewBuilder
    private func inlineAddStepForm() -> some View {
        VStack(spacing: 10) {
            Divider()

            HStack {
                DatePicker("", selection: $newStepTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .frame(width: 100)

                TextField("Action", text: $newStepAction)
                    .focused($isNewStepActionFocused)
                    .textInputAutocapitalization(.words)
                    .textFieldStyle(.roundedBorder)
            }

            TextField("Note (optional)", text: $newStepNote)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    resetAddStep()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button("Add") {
                    saveNewStep()
                }
                .bold()
                .disabled(newStepAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func saveNewStep() {
        guard let pending else { return }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let trimmedAction = newStepAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = newStepNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAction.isEmpty else { return }

        var schedulePayload = pending.payload.schedule ?? []
        schedulePayload.append(
            ScheduleEntryPayload(
                time: timeFormatter.string(from: newStepTime),
                action: trimmedAction,
                note: trimmedNote.isEmpty ? nil : trimmedNote
            )
        )

        let updatedPayload = CreateBakePayload(
            title: pending.payload.title,
            bakeDate: pending.payload.bakeDate,
            ingredientsText: pending.payload.ingredientsText,
            ingredients: pending.payload.ingredients,
            notes: pending.payload.notes,
            schedule: schedulePayload
        )

        syncManager.updatePending(
            id: pending.id,
            payload: updatedPayload,
            imageDataItems: pending.imageDataItems
        )

        resetAddStep()
    }

    private func resetAddStep() {
        showingAddStep = false
        isNewStepActionFocused = false
        newStepTime = .now
        newStepAction = ""
        newStepNote = ""
    }

    private func addSelectedPhotosToPending() async {
        guard !selectedPhotos.isEmpty else { return }
        let items = selectedPhotos

        isAddingPhotos = true
        defer {
            isAddingPhotos = false
            selectedPhotos.removeAll()
        }

        var addedImages: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                addedImages.append(data)
            }
        }
        guard !addedImages.isEmpty else { return }
        guard let latestPending = syncManager.pendingBakes.first(where: { $0.id == pendingId }) else { return }

        var updatedImages = latestPending.imageDataItems
        updatedImages.append(contentsOf: addedImages)

        syncManager.updatePending(
            id: latestPending.id,
            payload: latestPending.payload,
            imageDataItems: updatedImages
        )
    }

    private func saveNotesToPending() {
        guard let pending else { return }

        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let updatedPayload = CreateBakePayload(
            title: pending.payload.title,
            bakeDate: pending.payload.bakeDate,
            ingredientsText: pending.payload.ingredientsText,
            ingredients: pending.payload.ingredients,
            notes: trimmed.isEmpty ? nil : trimmed,
            schedule: pending.payload.schedule
        )

        syncManager.updatePending(
            id: pending.id,
            payload: updatedPayload,
            imageDataItems: pending.imageDataItems
        )
    }
}
