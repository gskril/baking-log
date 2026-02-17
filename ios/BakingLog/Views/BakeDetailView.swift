import SwiftUI

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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let bake {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Photos
                        if let photos = bake.photos, !photos.isEmpty {
                            PhotoCarousel(photos: photos)
                        }

                        // Ingredients
                        ingredientsSection(bake: bake)

                        // Schedule
                        scheduleSection(bake: bake)

                        // Notes
                        if let notes = bake.notes, !notes.isEmpty {
                            SectionBlock(title: "Notes") {
                                Text(notes)
                                    .font(.body)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle(bake?.title ?? "Bake")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if bake != nil {
                Button("Edit") {
                    showingEdit = true
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
                } label: {
                    Label("Add Step", systemImage: "plus.circle")
                        .font(.subheadline)
                }
                .padding(.top, 4)
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
        schedulePayload.append(
            ScheduleEntryPayload(
                time: timeFormatter.string(from: newStepTime),
                action: newStepAction,
                note: newStepNote.isEmpty ? nil : newStepNote
            )
        )

        // Build ingredients payload to preserve them
        let ingredientsPayload = bake.ingredients?.map {
            IngredientPayload(name: $0.name, amount: $0.amount, note: $0.note)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let payload = CreateBakePayload(
            title: bake.title,
            bakeDate: bake.bakeDate,
            ingredientsText: bake.ingredientsText,
            ingredients: ingredientsPayload,
            notes: bake.notes,
            schedule: schedulePayload
        )

        _ = try? await APIClient.shared.updateBake(id: bake.id, payload)
        resetAddStep()
        isSavingStep = false
        await load()
    }

    private func resetAddStep() {
        showingAddStep = false
        newStepTime = .now
        newStepAction = ""
        newStepNote = ""
    }

    private func load() async {
        isLoading = true
        bake = try? await APIClient.shared.getBake(id: bakeId)
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
