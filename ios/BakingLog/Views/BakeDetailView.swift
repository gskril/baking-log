import SwiftUI
import PhotosUI

struct BakeDetailView: View {
    let bakeId: String
    let initialTitle: String?
    @State private var viewModel: BakeDetailViewModel
    @State private var showingEdit = false
    @State private var showingAddStep = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @FocusState private var isNewStepActionFocused: Bool

    init(bakeId: String, initialTitle: String?) {
        self.bakeId = bakeId
        self.initialTitle = initialTitle
        _viewModel = State(initialValue: BakeDetailViewModel(bakeId: bakeId))
    }

    private var isShowingActionError: Binding<Bool> {
        Binding {
            viewModel.actionError != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.actionError = nil
            }
        }
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.bake == nil {
                ProgressView()
            } else if let bake = viewModel.bake {
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
                .alert("Something Went Wrong", isPresented: isShowingActionError, presenting: viewModel.actionError) { _ in
                    Button("OK", role: .cancel) {}
                } message: { error in
                    Text(error)
                }
            } else {
                ContentUnavailableView {
                    Label("Bake Unavailable", systemImage: "wifi.slash")
                } description: {
                    Text(viewModel.loadError ?? "Could not load this bake.")
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                }
            }
        }
        .navigationTitle(viewModel.bake?.title ?? initialTitle ?? "Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if viewModel.bake != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        showingEdit = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let bake = viewModel.bake {
                BakeEditView(existing: bake) {
                    showingEdit = false
                    Task { await viewModel.load() }
                }
            }
        }
        .task {
            await viewModel.load()
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
            .disabled(viewModel.isUploadingPhotos)

            if viewModel.isUploadingPhotos {
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
                    VStack(alignment: .leading, spacing: 8) {
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
            }

            if showingAddStep {
                inlineAddStepForm()
            } else {
                Button {
                    // Default to the last step's time so the new step lands on the right day.
                    viewModel.newStepTime = bake.schedule?.last?.date ?? .now
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
        let notesChanged = viewModel.editedNotes != currentNotes

        SectionBlock(title: "Notes") {
            // Grows with content so the caret never scrolls out of sight
            // inside a fixed-height box.
            TextField("Notes", text: $viewModel.editedNotes, axis: .vertical)
                .lineLimit(4...)
                .padding(8)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.quaternary)
                }

            HStack {
                Button("Reset") {
                    viewModel.editedNotes = currentNotes
                }
                .foregroundStyle(.secondary)
                .disabled(!notesChanged || viewModel.isSavingNotes)

                Spacer()

                Button {
                    Task { await viewModel.saveNotes() }
                } label: {
                    if viewModel.isSavingNotes {
                        ProgressView()
                    } else {
                        Text("Save Notes").bold()
                    }
                }
                .disabled(!notesChanged || viewModel.isSavingNotes)
            }
        }
    }

    // MARK: - Inline Add Step

    @ViewBuilder
    private func inlineAddStepForm() -> some View {
        VStack(spacing: 10) {
            Divider()

            TextField("Action", text: $viewModel.newStepAction)
                .focused($isNewStepActionFocused)
                .textInputAutocapitalization(.sentences)
                .textFieldStyle(.roundedBorder)

            // Empty title on purpose: even with labelsHidden, a real title
            // reserves layout space on newly inserted rows (gap + compressed
            // date format), so the VoiceOver label is applied separately.
            DatePicker("", selection: $viewModel.newStepTime, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .accessibilityLabel("Time")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Note (optional)", text: $viewModel.newStepNote)
                .font(.caption)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    resetAddStepPresentation()
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    Task { await saveNewStep() }
                } label: {
                    if viewModel.isSavingStep {
                        ProgressView()
                    } else {
                        Text("Add")
                            .bold()
                    }
                }
                .disabled(viewModel.newStepAction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSavingStep)
            }
        }
        .padding(.top, 4)
    }

    private func saveNewStep() async {
        if await viewModel.saveNewStep() {
            showingAddStep = false
            isNewStepActionFocused = false
        }
    }

    private func uploadSelectedPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        let items = selectedPhotos
        selectedPhotos.removeAll()
        await viewModel.uploadPhotos(items)
    }

    private func resetAddStepPresentation() {
        showingAddStep = false
        isNewStepActionFocused = false
        viewModel.resetAddStep()
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
                    Button {
                        selectedPhoto = photo
                    } label: {
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
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(photo.caption ?? "Photo")
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
    @State private var dragOffset: CGFloat = 0

    private var backdropOpacity: Double {
        1 - min(abs(dragOffset) / 800, 1)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .opacity(backdropOpacity)

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
            .offset(y: dragOffset)
            .gesture(
                DragGesture()
                    .onChanged { dragOffset = $0.translation.height }
                    .onEnded { value in
                        if abs(value.translation.height) > 120 {
                            let direction: CGFloat = value.translation.height > 0 ? 1 : -1
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = direction * 1200
                            }
                            Task {
                                try? await Task.sleep(for: .seconds(0.2))
                                // The system dismiss transition always slides down,
                                // which fights an upward swipe — suppress it.
                                var transaction = Transaction()
                                transaction.disablesAnimations = true
                                withTransaction(transaction) { dismiss() }
                            }
                        } else {
                            withAnimation(.spring) { dragOffset = 0 }
                        }
                    }
            )
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white)
            }
            .padding()
            .opacity(backdropOpacity)
        }
        .presentationBackground(.clear)
    }
}
