import SwiftUI
import PhotosUI

struct BakeEditView: View {
    @StateObject private var vm = BakeEditViewModel()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var pendingIngredientFocusId: UUID?
    @State private var hasLoadedInitialData = false
    @FocusState private var focusedIngredientField: IngredientField?
    let existing: Bake?
    let prefill: BakeEditViewModel.Prefill?
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    enum IngredientField: Hashable {
        case name(UUID)
        case amount(UUID)
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
                            focusedField: $focusedIngredientField
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
                        ScheduleEntryRow(entry: $entry)
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
                    if !vm.newImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(vm.newImages.indices, id: \.self) { i in
                                    Image(uiImage: vm.newImages[i])
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 80, height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                vm.newImages.remove(at: i)
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
                    Button(vm.isEditing ? "Save" : "Create") {
                        submitPrimaryAction()
                    }
                    .disabled(!hasLoadedInitialData || vm.isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedIngredientField = nil
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
                    focusedIngredientField = .name(id)
                }
            }
            .interactiveDismissDisabled(vm.isSaving)
        }
    }

    private func submitPrimaryAction() {
        // Commit any in-flight field edits before building the save payload.
        focusedIngredientField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

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
        for item in selectedPhotos {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                vm.newImages.append(image)
            }
        }
        selectedPhotos.removeAll()
    }
}

struct IngredientEntryRow: View {
    @Binding var entry: BakeEditViewModel.EditableIngredient
    var focusedField: FocusState<BakeEditView.IngredientField?>.Binding

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $entry.name)
                    .focused(focusedField, equals: .name(entry.id))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField.wrappedValue = .amount(entry.id)
                    }

                TextField("Amount", text: $entry.amountValue)
                    .focused(focusedField, equals: .amount(entry.id))
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct ScheduleEntryRow: View {
    @Binding var entry: BakeEditViewModel.EditableScheduleEntry

    var body: some View {
        VStack(spacing: 8) {
            TextField("Action (e.g., Mix, fold, shape)", text: $entry.action)
                .textInputAutocapitalization(.sentences)

            DatePicker("", selection: $entry.timeDate, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Note (optional)", text: $entry.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
