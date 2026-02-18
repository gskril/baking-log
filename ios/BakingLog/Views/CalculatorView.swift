import SwiftUI

struct CalculatorView: View {
    @StateObject private var vm = CalculatorViewModel()
    @FocusState private var focusedField: IngredientField?
    @State private var pendingIngredientFocusId: UUID?
    @State private var showingNewBake = false
    @State private var bakePrefill: BakeEditViewModel.Prefill?

    enum IngredientField: Hashable {
        case name(UUID)
        case weight(UUID)
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
                        .keyboardType(.decimalPad)

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
                    bakePrefill = makeBakePrefill()
                    showingNewBake = bakePrefill != nil
                } label: {
                    Label("New Bake", systemImage: "text.badge.plus")
                }
                .disabled(!canCreateBakePrefill)
            }
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingNewBake, onDismiss: { bakePrefill = nil }) {
            if let bakePrefill {
                BakeEditView(prefill: bakePrefill) {
                    showingNewBake = false
                }
            }
        }
    }

    private var canCreateBakePrefill: Bool {
        !prefillIngredients().isEmpty
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
                    .textInputAutocapitalization(.words)
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
                    .keyboardType(.decimalPad)
                    .font(.body.monospacedDigit())

                Text("g")
                    .foregroundStyle(.secondary)

                Spacer()

                if ingredient.weightGrams > 0 {
                    Text(String(format: "%.1f%%", percentage))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func colorForRole(_ role: CalculatorViewModel.Ingredient.Role) -> Color {
        switch role {
        case .flour: .brown
        case .liquid: .blue
        case .other: .secondary
        }
    }
}
