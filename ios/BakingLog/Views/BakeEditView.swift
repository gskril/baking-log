import SwiftUI
import PhotosUI

struct BakeEditView: View {
    @StateObject private var vm = BakeEditViewModel()
    @State private var selectedPhotos: [PhotosPickerItem] = []
    let existing: Bake?
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(existing: Bake? = nil, onDismiss: @escaping () -> Void) {
        self.existing = existing
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationStack {
            Form {
                // Basic Info
                Section {
                    TextField("Title", text: $vm.title)
                        .textInputAutocapitalization(.words)

                    DatePicker("Date", selection: $vm.bakeDate, displayedComponents: .date)
                }

                // Ingredients
                Section("Ingredients") {
                    TextEditor(text: $vm.ingredients)
                        .frame(minHeight: 120)
                        .font(.body.monospaced())
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
                    // Existing photos
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
                                                .font(.caption)
                                                .foregroundStyle(.red)
                                        }
                                        .offset(x: 4, y: -4)
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
                                                    .font(.caption)
                                                    .foregroundStyle(.red)
                                            }
                                            .offset(x: 4, y: -4)
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
                    TextEditor(text: $vm.notes)
                        .frame(minHeight: 80)
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isEditing ? "Save" : "Create") {
                        Task {
                            if await vm.save() != nil {
                                dismiss()
                                onDismiss()
                            }
                        }
                    }
                    .disabled(vm.title.isEmpty || vm.isSaving)
                }
            }
            .onAppear {
                if let existing {
                    vm.loadExisting(existing)
                }
            }
            .interactiveDismissDisabled(vm.isSaving)
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

struct ScheduleEntryRow: View {
    @Binding var entry: BakeEditViewModel.EditableScheduleEntry

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Time", text: $entry.time)
                    .frame(width: 90)
                    .textInputAutocapitalization(.never)

                TextField("Action (e.g., Mix, Fold, Shape)", text: $entry.action)
                    .textInputAutocapitalization(.words)
            }

            TextField("Note (optional)", text: $entry.note)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
