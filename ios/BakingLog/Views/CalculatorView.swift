import SwiftUI

struct CalculatorView: View {
    @StateObject private var vm = CalculatorViewModel()

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
                        percentage: vm.bakersPercentage(for: ingredient)
                    )
                }
                .onDelete(perform: vm.removeIngredients)
                .onMove(perform: vm.moveIngredients)

                Button {
                    vm.addIngredient()
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
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

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("Name", text: $ingredient.name)
                    .textInputAutocapitalization(.words)

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
