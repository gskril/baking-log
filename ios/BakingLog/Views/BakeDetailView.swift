import SwiftUI
import PhotosUI

struct BakeDetailView: View {
    let bakeId: String
    let initialTitle: String?
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
    @State private var loadError: String?
    @State private var actionError: String?
    @FocusState private var isNewStepActionFocused: Bool

    private var isShowingActionError: Binding<Bool> {
        Binding {
            actionError != nil
        } set: { isPresented in
            if !isPresented {
                actionError = nil
            }
        }
    }

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
                // Keep the keyboard up while scrolling to see the notes field;
                // dragging down onto the keyboard still dismisses it.
                .scrollDismissesKeyboard(.interactively)
                .alert("Something Went Wrong", isPresented: isShowingActionError, presenting: actionError) { _ in
                    Button("OK", role: .cancel) {}
                } message: { error in
                    Text(error)
                }
            } else {
                ContentUnavailableView {
                    Label("Bake Unavailable", systemImage: "wifi.slash")
                } description: {
                    Text(loadError ?? "Could not load this bake.")
                } actions: {
                    Button("Retry") {
                        Task { await load() }
                    }
                }
            }
        }
        .navigationTitle(bake?.title ?? initialTitle ?? "Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if bake != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEdit = true
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
                            Text(ingredient.displayAmount)
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
    private func scheduleSection(bake: Bake) -> some View {
        SectionBlock(title: "Schedule") {
            if let schedule = bake.schedule, !schedule.isEmpty {
                let dates = schedule.map(\.date)
                ForEach(Array(schedule.enumerated()), id: \.element.id) { index, entry in
                    if let dayLabel = Formatters.dayLabel(in: dates, at: index) {
                        Text(dayLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .padding(.top, index == 0 ? 0 : 6)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text(Formatters.displayTime(entry.date))
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
                    // Default to the last step's time so the new step lands on the right day.
                    newStepTime = bake.schedule?.last?.date ?? .now
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
            // Grows with content so the caret never scrolls out of sight
            // inside a fixed-height box.
            TextField("Notes", text: $editedNotes, axis: .vertical)
                .lineLimit(4...)
                .padding(8)
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
    private func inlineAddStepForm() -> some View {
        VStack(spacing: 10) {
            Divider()

            TextField("Action", text: $newStepAction)
                .focused($isNewStepActionFocused)
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)

            DatePicker("", selection: $newStepTime, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

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
                    Task { await saveNewStep() }
                } label: {
                    if isSavingStep {
                        ProgressView()
                    } else {
                        Text("Add")
                            .bold()
                    }
                }
                .disabled(newStepAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingStep)
            }
        }
        .padding(.top, 4)
    }

    private func saveNewStep() async {
        guard let bake else { return }
        isSavingStep = true
        defer { isSavingStep = false }

        let trimmedAction = newStepAction.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = newStepNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAction.isEmpty else { return }

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
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func saveNotes() async {
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

    private func uploadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        guard let bake else {
            selectedPhotos.removeAll()
            return
        }

        isUploadingPhotos = true
        let items = selectedPhotos
        selectedPhotos.removeAll()

        var updatedBake = bake
        var failureCount = 0
        var lastError: Error?

        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    failureCount += 1
                    continue
                }
                let photo = try await APIClient.shared.uploadPhoto(bakeId: bake.id, imageData: data)

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
