import SwiftUI
import PhotosUI

struct BakeDetailView: View {
    let bakeId: String
    @State private var bake: Bake?
    @State private var isLoading = true
    @State private var showingEdit = false
    @State private var showingAddStep = false
    @State private var newStepTime: Date = .now
    @State private var newStepAction: String = ""
    @State private var newStepNote: String = ""
    @State private var isSavingStep = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var isUploadingPhotos = false
    @State private var editedNotes: String = ""
    @State private var isSavingNotes = false
    @FocusState private var isNewStepActionFocused: Bool
    @ObservedObject private var syncManager = SyncManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading && bake == nil {
                ProgressView()
            } else if let bake {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Photos
                        photosSection(bake: bake)

                        // Ingredients
                        ingredientsSection(bake: bake)

                        // Schedule
                        scheduleSection(bake: bake)

                        // Notes
                        notesSection(bake: bake)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(bake?.title ?? "Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if bake != nil {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        if syncManager.hasPendingChanges(for: bakeId) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                        Button("Edit") {
                            showingEdit = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let bake {
                BakeEditView(existing: bake) {
                    showingEdit = false
                    Task { await load() }
                }
            }
        }
        .task {
            await load()
        }
        .onChange(of: selectedPhotos) {
            Task { await uploadSelectedPhotos() }
        }
    }

    // MARK: - Photos Section

    @ViewBuilder
    private func photosSection(bake: Bake) -> some View {
        SectionBlock(title: "Photos") {
            if let photos = bake.photos, !photos.isEmpty {
                PhotoCarousel(photos: photos)
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
            .disabled(isUploadingPhotos)

            if isUploadingPhotos {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Uploading photos...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Ingredients Section

    @ViewBuilder
    private func ingredientsSection(bake: Bake) -> some View {
        if let structured = bake.ingredients, !structured.isEmpty {
            SectionBlock(title: "Ingredients") {
                ForEach(structured) { ingredient in
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
        } else if let text = bake.ingredientsText, !text.isEmpty {
            SectionBlock(title: "Ingredients") {
                Text(text)
                    .font(.body.monospaced())
            }
        }
    }

    // MARK: - Schedule Section

    @ViewBuilder
    private func scheduleSection(bake: Bake) -> some View {
        SectionBlock(title: "Schedule") {
            if let schedule = bake.schedule, !schedule.isEmpty {
                ForEach(schedule) { entry in
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
                inlineAddStepForm(bake: bake)
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

    // MARK: - Notes Section

    @ViewBuilder
    private func notesSection(bake: Bake) -> some View {
        let currentNotes = bake.notes ?? ""
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
                .disabled(!notesChanged || isSavingNotes)

                Spacer()

                Button {
                    Task { await saveNotes() }
                } label: {
                    if isSavingNotes {
                        ProgressView()
                    } else {
                        Text("Save Notes").bold()
                    }
                }
                .disabled(!notesChanged || isSavingNotes)
            }
        }
    }

    // MARK: - Inline Add Step

    @ViewBuilder
    private func inlineAddStepForm(bake: Bake) -> some View {
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

                Button {
                    Task { await saveNewStep(bake: bake) }
                } label: {
                    if isSavingStep {
                        ProgressView()
                    } else {
                        Text("Add")
                            .bold()
                    }
                }
                .disabled(newStepAction.isEmpty || isSavingStep)
            }
        }
        .padding(.top, 4)
    }

    private func saveNewStep(bake: Bake) async {
        isSavingStep = true

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        // Build schedule: existing entries + new entry
        var schedulePayload = (bake.schedule ?? []).map {
            ScheduleEntryPayload(time: $0.time, action: $0.action, note: $0.note)
        }
        let newEntry = ScheduleEntryPayload(
            time: timeFormatter.string(from: newStepTime),
            action: newStepAction,
            note: newStepNote.isEmpty ? nil : newStepNote
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
        } catch {
            // Offline: apply optimistic local update
            let newScheduleEntry = ScheduleEntry(
                id: "local-\(UUID().uuidString)",
                bakeId: bake.id,
                time: timeFormatter.string(from: newStepTime),
                action: newStepAction,
                note: newStepNote.isEmpty ? nil : newStepNote,
                sortOrder: (bake.schedule?.count ?? 0)
            )
            var updated = bake
            var schedule = updated.schedule ?? []
            schedule.append(newScheduleEntry)
            updated.schedule = schedule
            self.bake = updated

            syncManager.queueUpdate(bakeId: bake.id, payload: payload)
        }

        resetAddStep()
        isSavingStep = false
    }

    private func saveNotes() async {
        guard let bake else { return }
        isSavingNotes = true

        let trimmed = editedNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmed.isEmpty ? nil : editedNotes
        let existingSchedule = (bake.schedule ?? []).map {
            ScheduleEntryPayload(time: $0.time, action: $0.action, note: $0.note)
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
            // Offline: apply optimistic local update
            var updated = bake
            updated.notes = noteValue
            self.bake = updated

            syncManager.queueUpdate(bakeId: bake.id, payload: payload)
        }

        isSavingNotes = false
    }

    private func uploadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        guard let bake else {
            selectedPhotos.removeAll()
            return
        }

        isUploadingPhotos = true
        let items = selectedPhotos
        selectedPhotos.removeAll()

        var failedData: [Data] = []
        var updatedBake = bake

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            do {
                let photo = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: data)
                var photos = updatedBake.photos ?? []
                photos.append(photo)
                updatedBake.photos = photos
            } catch {
                failedData.append(data)
            }
        }

        self.bake = updatedBake

        if !failedData.isEmpty {
            syncManager.queuePhotoUpload(bakeId: bake.id, imageDataItems: failedData)
        }

        isUploadingPhotos = false
    }

    private func buildPayload(from bake: Bake, notes: String?, schedule: [ScheduleEntryPayload]?) -> CreateBakePayload {
        let ingredientsPayload = bake.ingredients?.map {
            IngredientPayload(name: $0.name, amount: $0.amount, note: $0.note)
        }

        return CreateBakePayload(
            title: bake.title,
            bakeDate: bake.bakeDate,
            ingredientsText: bake.ingredientsText,
            ingredients: ingredientsPayload,
            notes: notes,
            schedule: schedule
        )
    }

    private func resetAddStep() {
        showingAddStep = false
        isNewStepActionFocused = false
        newStepTime = .now
        newStepAction = ""
        newStepNote = ""
    }

    private func load() async {
        if bake == nil {
            isLoading = true
        }
        if let loaded = try? await APIClient.shared.getBake(id: bakeId) {
            bake = loaded
            editedNotes = loaded.notes ?? ""
        }
        isLoading = false
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title3.bold())
            content
        }
    }
}

struct PhotoCarousel: View {
    let photos: [Photo]
    @State private var selectedPhoto: Photo?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(photos) { photo in
                    AsyncImage(url: APIClient.shared.photoURL(for: photo.id)) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .failure:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        default:
                            Rectangle()
                                .fill(.quaternary)
                                .overlay { ProgressView() }
                        }
                    }
                    .frame(width: 280, height: 210)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { selectedPhoto = photo }
                }
            }
            .padding(.horizontal, 1)
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            FullScreenPhoto(photo: photo)
        }
    }
}

struct FullScreenPhoto: View {
    let photo: Photo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            AsyncImage(url: APIClient.shared.photoURL(for: photo.id)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                default:
                    ProgressView()
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding()
        }
    }
}
