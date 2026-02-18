import Foundation
import SwiftUI

@MainActor
class CalculatorViewModel: ObservableObject {
    @Published var ingredients: [Ingredient] = []
    @Published var targetDoughWeight: String = ""

    struct Ingredient: Identifiable {
        let id = UUID()
        var name: String
        var weight: String // grams, as string for text field binding
        var role: Role

        enum Role: String, CaseIterable {
            case flour = "Flour"
            case liquid = "Liquid"
            case starter = "Starter"
            case other = "Other"
        }

        var weightGrams: Double {
            Double(weight) ?? 0
        }
    }

    var totalFlour: Double {
        ingredients.reduce(0) { total, ing in
            switch ing.role {
            case .flour: total + ing.weightGrams
            case .starter: total + ing.weightGrams * 0.5
            default: total
            }
        }
    }

    var totalLiquid: Double {
        ingredients.reduce(0) { total, ing in
            switch ing.role {
            case .liquid: total + ing.weightGrams * 1.0
            case .starter: total + ing.weightGrams * 0.5
            default: total
            }
        }
    }

    var totalWeight: Double {
        ingredients.reduce(0) { $0 + $1.weightGrams }
    }

    var hydration: Double {
        guard totalFlour > 0 else { return 0 }
        return (totalLiquid / totalFlour) * 100
    }

    func bakersPercentage(for ingredient: Ingredient) -> Double {
        guard totalFlour > 0 else { return 0 }
        if ingredient.role == .flour && ingredients.filter({ $0.role == .flour }).count == 1 {
            return 100
        }
        return (ingredient.weightGrams / totalFlour) * 100
    }

    func addIngredient() {
        ingredients.append(Ingredient(name: "", weight: "", role: .other))
    }

    func removeIngredients(at offsets: IndexSet) {
        ingredients.remove(atOffsets: offsets)
    }

    func moveIngredients(from source: IndexSet, to destination: Int) {
        ingredients.move(fromOffsets: source, toOffset: destination)
    }

    func scaleToTarget() {
        guard let target = Double(targetDoughWeight), target > 0, totalWeight > 0 else { return }
        let factor = target / totalWeight
        for i in ingredients.indices {
            let scaled = ingredients[i].weightGrams * factor
            ingredients[i].weight = formatWeight(scaled)
        }
    }

    func scaleByFlour() {
        guard let target = Double(targetDoughWeight), target > 0, totalFlour > 0 else { return }
        let factor = target / totalFlour
        for i in ingredients.indices {
            let scaled = ingredients[i].weightGrams * factor
            ingredients[i].weight = formatWeight(scaled)
        }
        targetDoughWeight = ""
    }

    func loadPreset(_ preset: Preset) {
        ingredients = preset.ingredients
        targetDoughWeight = ""
    }

    private func formatWeight(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    // MARK: - Presets

    enum Preset: String, CaseIterable, Identifiable {
        case sourdough = "Sourdough"
        case pizza = "Pizza Dough"
        case focaccia = "Focaccia"

        var id: String { rawValue }

        var ingredients: [Ingredient] {
            switch self {
            case .sourdough:
                return [
                    Ingredient(name: "Bread flour", weight: "200", role: .flour),
                    Ingredient(name: "All purpose flour", weight: "200", role: .flour),
                    Ingredient(name: "Rye flour", weight: "50", role: .flour),
                    Ingredient(name: "Whole wheat", weight: "50", role: .flour),
                    Ingredient(name: "Water", weight: "362.5", role: .liquid),
                    Ingredient(name: "Starter", weight: "100", role: .starter),
                    Ingredient(name: "Salt", weight: "11", role: .other),
                ]
            case .pizza:
                return [
                    Ingredient(name: "Bread flour", weight: "500", role: .flour),
                    Ingredient(name: "Water", weight: "325", role: .liquid),
                    Ingredient(name: "Olive oil", weight: "15", role: .other),
                    Ingredient(name: "Yeast", weight: "3", role: .other),
                    Ingredient(name: "Salt", weight: "10", role: .other),
                    Ingredient(name: "Sugar", weight: "10", role: .other),
                ]
            case .focaccia:
                return [
                    Ingredient(name: "Bread flour", weight: "500", role: .flour),
                    Ingredient(name: "Water", weight: "400", role: .liquid),
                    Ingredient(name: "Olive oil", weight: "30", role: .other),
                    Ingredient(name: "Yeast", weight: "4", role: .other),
                    Ingredient(name: "Salt", weight: "10", role: .other),
                ]
            }
        }
    }
}
