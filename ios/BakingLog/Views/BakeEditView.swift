import SwiftUI
import PhotosUI

struct BakeEditView: View {
    @State private var vm = BakeEditViewModel()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingIngredientFocusId: UUID?
    @State private var hasLoadedInitialData = false
    @FocusState private var focusedField: Field?
    let existing: Bake?
    let prefill: BakeEditViewModel.Prefill?
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum Field: Hashable {
        case title
        case notes
        case ingredientName(UUID)
        case ingredientAmount(UUID)
        case ingredientNote(UUID)
        case scheduleAction(UUID)
        case scheduleNote(UUID)
    }

    init(existing: Bake? = nil, onDismiss: @escaping () -> Void) {
        self.existing = existing
        self.prefill = nil
        self.onDismiss = onDismiss
    }

    init(prefill: BakeEditViewModel.Prefill, onDismiss: @escaping () -> Void) {
        self.existing = nil
        self.prefill = prefill
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section {
                    TextField("Title", text: $vm.title)
                        .focused($focusedField, equals: .title)
                        .textInputAutocapitalization(.sentences)
                        .overlay(alignment: .trailing) {
                            if !vm.title.isEmpty {
                                Button {
                                    vm.title = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                    DatePicker("Start Date", selection: $vm.bakeDate, displayedComponents: .date)
                }

                // Ingredients
                Section {
                    ForEach($vm.ingredientEntries) { $entry in
                        IngredientEntryRow(
                            entry: $entry,
                            focusedField: $focusedField
                        )
                    }
                    .onDelete(perform: vm.removeIngredient)
                    .onMove(perform: vm.moveIngredient)

                    Button {
                        vm.addIngredient()
                        pendingIngredientFocusId = vm.ingredientEntries.last?.id
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Ingredients")
                }

                // Schedule
                Section {
                    ForEach($vm.scheduleEntries) { $entry in
                        ScheduleEntryRow(
                            entry: $entry,
                            focusedField: $focusedField
                        )
                    }
                    .onDelete(perform: vm.removeScheduleEntry)
                    .onMove(perform: vm.moveScheduleEntry)

                    Button {
                        vm.addScheduleEntry()
                    } label: {
                        Label("Add Step", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Schedule")
                }

                // Photos
                Section("Photos") {
                    // Existing server photos
                    if !vm.existingPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.existingPhotos) { photo in
                                    AsyncImage(url: APIClient.shared.photoURL(for: photo.id)) { phase in
                                        if case .success(let image) = phase {
                                            image.resizable().aspectRatio(contentMode: .fill)
                                        } else {
                                            Rectangle().fill(.quaternary)
                                        }
                                    }
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .topTrailing) {
                                        Button {
                                            Task { await vm.deleteExistingPhoto(photo) }
                                        } label: {
                                            Image(systemName: "minus.circle.fill")
                                                .font(.body)
                                                .foregroundStyle(.red)
                                                .background(Circle().fill(.white).padding(2))
                                        }
                                        .padding(4)
                                    }
                                }
                            }
                        }
                    }

                    // New photos
                    if !vm.pendingPhotos.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.pendingPhotos) { photo in
                                    Image(uiImage: photo.thumbnail)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                vm.removePendingPhoto(id: photo.id)
                                            } label: {
                                                Image(systemName: "minus.circle.fill")
                                                    .font(.body)
                                                    .foregroundStyle(.red)
                                                    .background(Circle().fill(.white).padding(2))
                                            }
                                            .padding(4)
                                        }
                                }
                            }
                        }
                    }

                    PhotosPicker(
                        selection: $selectedPhotos,
                        maxSelectionCount: 10,
                        matching: .images
                    ) {
                        Label("Add Photos", systemImage: "photo.on.rectangle.angled")
                    }
                    .onChange(of: selectedPhotos) {
                        Task { await loadPhotos() }
                    }
                }

                // Notes
                Section("Notes") {
                    // Vertical-axis TextField grows with its content (unlike a
                    // fixed-height TextEditor, which scrolls internally and lets
                    // the caret drift out of view under the keyboard).
                    TextField("Notes", text: $vm.notes, axis: .vertical)
                        .focused($focusedField, equals: .notes)
                        .lineLimit(7...)
                        .textInputAutocapitalization(.sentences)
                }

                if let error = vm.error {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(vm.isEditing ? "Edit Bake" : "New Bake")
            .navigationBarTitleDisplayMode(.inline)
            // Only dismiss the keyboard when dragging down onto it — scrolling
            // up to see more of a field should never hide the keyboard.
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button(vm.isEditing ? "Save" : "Create") {
                            submitPrimaryAction()
                        }
                        .disabled(!hasLoadedInitialData)
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .onAppear {
                guard !hasLoadedInitialData else { return }
                hasLoadedInitialData = true

                if let existing {
                    vm.loadExisting(existing)
                } else if let prefill {
                    vm.loadPrefill(prefill)
                }
            }
            .onChange(of: vm.ingredientEntries.count) {
                guard let id = pendingIngredientFocusId else { return }
                pendingIngredientFocusId = nil
                DispatchQueue.main.async {
                    focusedField = .ingredientName(id)
                }
            }
            .interactiveDismissDisabled(vm.isSaving)
            // The inline error section can sit below the fold on a long form,
            // so also raise an alert the moment an action fails.
            .alert("Something Went Wrong", isPresented: isShowingError, presenting: vm.error) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error)
            }
            .offlineBanner()
        }
    }

    private var isShowingError: Binding<Bool> {
        Binding {
            vm.error != nil && !vm.isSaving
        } set: { isPresented in
            if !isPresented {
                vm.error = nil
            }
        }
    }

    private func submitPrimaryAction() {
        // Commit any in-flight field edits before building the save payload.
        focusedField = nil

        Task { @MainActor in
            await Task.yield()
            if await vm.save() != nil {
                dismiss()
                onDismiss()
            }
        }
    }

    private func loadPhotos() async {
        guard !selectedPhotos.isEmpty else { return }
        let items = selectedPhotos
        selectedPhotos.removeAll()
        // Loads, downsamples, and JPEG-encodes each photo; failures are
        // counted and surfaced via vm.error instead of silently dropped.
        await vm.addPhotos(items)
    }
}

struct IngredientEntryRow: View {
    @Binding var entry: BakeEditViewModel.EditableIngredient
    var focusedField: FocusState<BakeEditView.Field?>.Binding

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $entry.name)
                    .focused(focusedField, equals: .ingredientName(entry.id))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField.wrappedValue = .ingredientAmount(entry.id)
                    }

                TextField("Amount", text: $entry.amountValue)
                    .focused(focusedField, equals: .ingredientAmount(entry.id))
                    .frame(width: 72)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .multilineTextAlignment(.trailing)

                Picker("Unit", selection: $entry.unit) {
                    ForEach(BakeEditViewModel.IngredientUnit.allCases) { unit in
                        Text(unit.rawValue).tag(unit)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if !entry.note.isEmpty || entry.name.isEmpty {
                TextField("Note (optional)", text: $entry.note)
                    .focused(focusedField, equals: .ingredientNote(entry.id))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScheduleEntryRow: View {
    @Binding var entry: BakeEditViewModel.EditableScheduleEntry
    var focusedField: FocusState<BakeEditView.Field?>.Binding

    var body: some View {
        VStack(spacing: 8) {
            TextField("Action (e.g., Mix, fold, shape)", text: $entry.action)
                .focused(focusedField, equals: .scheduleAction(entry.id))
                .textInputAutocapitalization(.sentences)

            // Empty title on purpose: even with labelsHidden, a real title
            // reserves layout space on newly inserted rows (gap + compressed
            // date format), so the VoiceOver label is applied separately.
            DatePicker("", selection: $entry.timeDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .accessibilityLabel("Time")
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Note (optional)", text: $entry.note)
                .focused(focusedField, equals: .scheduleNote(entry.id))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
