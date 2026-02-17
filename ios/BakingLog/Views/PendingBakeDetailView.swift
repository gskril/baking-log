import SwiftUI

struct PendingBakeDetailView: View {
    let pendingId: String
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var showingEdit = false
    @State private var showingAddStep = false
    @State private var newStepTime: Date = .now
    @State private var newStepAction: String = ""
    @State private var newStepNote: String = ""
    @Environment(\.dismiss) private var dismiss

    private var pending: SyncManager.PendingBake? {
        syncManager.pendingBakes.first { $0.id == pendingId }
    }

    var body: some View {
        Group {
            if let pending {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Local photos
                        if !pending.imageDataItems.isEmpty {
                            localPhotosSection(pending.imageDataItems)
                        }

                        // Ingredients
                        ingredientsSection(pending.payload)

                        // Schedule
                        scheduleSection(pending)

                        // Notes
                        if let notes = pending.payload.notes, !notes.isEmpty {
                            SectionBlock(title: "Notes") {
                                Text(notes)
                                    .font(.body)
                            }
                        }
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
    }

    // MARK: - Local Photos

    @ViewBuilder
    private func localPhotosSection(_ imageDataItems: [Data]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(imageDataItems.indices, id: \.self) { i in
                    if let uiImage = UIImage(data: imageDataItems[i]) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 280, height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(.horizontal, 1)
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
    private func inlineAddStepForm() -> some View {
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

                Button("Add") {
                    saveNewStep()
                }
                .bold()
                .disabled(newStepAction.isEmpty)
            }
        }
        .padding(.top, 4)
    }

    private func saveNewStep() {
        guard let pending else { return }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"

        var schedulePayload = pending.payload.schedule ?? []
        schedulePayload.append(
            ScheduleEntryPayload(
                time: timeFormatter.string(from: newStepTime),
                action: newStepAction,
                note: newStepNote.isEmpty ? nil : newStepNote
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
        newStepTime = .now
        newStepAction = ""
        newStepNote = ""
    }
}
