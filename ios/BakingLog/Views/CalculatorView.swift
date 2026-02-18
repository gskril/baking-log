import SwiftUI

struct CalculatorView: View {
    @StateObject private var vm = CalculatorViewModel()
    @FocusState private var focusedField: IngredientField?
    @State private var pendingIngredientFocusId: UUID?
    @State private var presentedDraft: PrefillDraft?
    @State private var showingMissingIngredientsAlert = false

    enum IngredientField: Hashable {
        case name(UUID)
        case weight(UUID)
    }

    private struct PrefillDraft: Identifiable {
        let id = UUID()
        let prefill: BakeEditViewModel.Prefill
    }

    var body: some View {
        Form {
            // Summary
            Section {
                HStack {
                    StatBadge(label: "Flour", value: "\(Int(vm.totalFlour))g")
                    StatBadge(label: "Hydration", value: String(format: "%.0f%%", vm.hydration))
                    StatBadge(label: "Total", value: "\(Int(vm.totalWeight))g")
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            // Ingredients
            Section {
                ForEach($vm.ingredients) { $ingredient in
                    IngredientRow(
                        ingredient: $ingredient,
                        percentage: vm.bakersPercentage(for: ingredient),
                        focusedField: $focusedField
                    )
                }
                .onDelete(perform: vm.removeIngredients)
                .onMove(perform: vm.moveIngredients)

                Button {
                    vm.addIngredient()
                    pendingIngredientFocusId = vm.ingredients.last?.id
                } label: {
                    Label("Add Ingredient", systemImage: "plus.circle")
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    Text("Baker's %")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Scaling
            Section("Scale") {
                HStack {
                    TextField("Target weight (g)", text: $vm.targetDoughWeight)

                    Button("Dough") {
                        vm.scaleToTarget()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.targetDoughWeight.isEmpty)

                    Button("Flour") {
                        vm.scaleByFlour()
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.targetDoughWeight.isEmpty)
                }
            }

            // Presets
            Section("Presets") {
                ForEach(CalculatorViewModel.Preset.allCases) { preset in
                    Button(preset.rawValue) {
                        vm.loadPreset(preset)
                    }
                }
            }
        }
        .navigationTitle("Calculator")
        .onChange(of: vm.ingredients.count) {
            guard let id = pendingIngredientFocusId else { return }
            pendingIngredientFocusId = nil
            DispatchQueue.main.async {
                focusedField = .name(id)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentNewBakeFromCalculator()
                } label: {
                    Label("New Bake", systemImage: "text.badge.plus")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .sheet(item: $presentedDraft) { draft in
            BakeEditView(prefill: draft.prefill) {
                presentedDraft = nil
            }
        }
        .alert("Add Ingredient Weights First", isPresented: $showingMissingIngredientsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enter at least one ingredient with a weight before creating a bake from the calculator.")
        }
    }

    private func presentNewBakeFromCalculator() {
        // Force any active text field edit to commit before reading vm.ingredients.
        focusedField = nil
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        Task { @MainActor in
            await Task.yield()
            guard let prefill = makeBakePrefill() else {
                showingMissingIngredientsAlert = true
                return
            }
            presentedDraft = PrefillDraft(prefill: prefill)
        }
    }

    private func makeBakePrefill() -> BakeEditViewModel.Prefill? {
        let ingredientEntries = prefillIngredients()
        guard !ingredientEntries.isEmpty else { return nil }

        return BakeEditViewModel.Prefill(
            title: "Calculator Bake",
            ingredientEntries: ingredientEntries,
            notes: nil
        )
    }

    private func prefillIngredients() -> [BakeEditViewModel.EditableIngredient] {
        vm.ingredients.compactMap { ingredient in
            let name = ingredient.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let amount = ingredient.weight.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !amount.isEmpty else { return nil }
            return BakeEditViewModel.EditableIngredient(
                name: name.isEmpty ? ingredient.role.rawValue : name,
                amountValue: amount,
                unit: .grams,
                note: ""
            )
        }
    }
}

struct StatBadge: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct IngredientRow: View {
    @Binding var ingredient: CalculatorViewModel.Ingredient
    let percentage: Double
    var focusedField: FocusState<CalculatorView.IngredientField?>.Binding

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $ingredient.name)
                    .focused(focusedField, equals: .name(ingredient.id))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField.wrappedValue = .weight(ingredient.id)
                    }

                Picker("", selection: $ingredient.role) {
                    ForEach(CalculatorViewModel.Ingredient.Role.allCases, id: \.self) { role in
                        Text(role.rawValue).tag(role)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(colorForRole(ingredient.role))
            }

            HStack {
                TextField("0", text: $ingredient.weight)
                    .focused(focusedField, equals: .weight(ingredient.id))
                    .font(.body.monospacedDigit())

                Text("g")
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    private func colorForRole(_ role: CalculatorViewModel.Ingredient.Role) -> Color {
        switch role {
        case .flour: .brown
        case .liquid: .blue
        case .starter: .orange
        case .other: .secondary
        }
    }
}
