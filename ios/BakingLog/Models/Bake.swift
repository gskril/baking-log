import Foundation

struct Bake: Identifiable, Codable, Hashable {
    let id: String
    var title: String?
    var bakeDate: String
    var ingredientsText: String?
    var ingredients: [Ingredient]?
    var ingredientCount: Int?
    var notes: String?
    var schedule: [ScheduleEntry]?
    var photos: [Photo]?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, ingredients, notes, schedule, photos
        case bakeDate = "bake_date"
        case ingredientsText = "ingredients_text"
        case ingredientCount = "ingredient_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayDate: String {
        // Parse ISO date and display nicely
        let parts = bakeDate.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return bakeDate
        }
        let year = String(parts[0].suffix(2))
        return "\(month)/\(day)/\(year)"
    }

    static let example = Bake(
        id: "preview-1",
        title: "Sourdough Loaf",
        bakeDate: "2026-02-13",
        ingredientsText: "90g starter\n325g water\n10g salt\n45g whole wheat\n45g rye\n360g white flour (half ap, half bread)",
        ingredients: [
            Ingredient(id: "i1", bakeId: "preview-1", name: "Starter", amount: "90g", note: nil, sortOrder: 0),
            Ingredient(id: "i2", bakeId: "preview-1", name: "Water", amount: "325g", note: nil, sortOrder: 1),
            Ingredient(id: "i3", bakeId: "preview-1", name: "Salt", amount: "10g", note: nil, sortOrder: 2),
            Ingredient(id: "i4", bakeId: "preview-1", name: "Whole Wheat", amount: "45g", note: nil, sortOrder: 3),
            Ingredient(id: "i5", bakeId: "preview-1", name: "Rye", amount: "45g", note: nil, sortOrder: 4),
            Ingredient(id: "i6", bakeId: "preview-1", name: "White Flour", amount: "360g", note: "half ap, half bread", sortOrder: 5),
        ],
        ingredientCount: nil,
        notes: nil,
        schedule: [
            ScheduleEntry(id: "s1", bakeId: "preview-1", time: "2:45pm", action: "Feed starter", note: nil, sortOrder: 0),
            ScheduleEntry(id: "s2", bakeId: "preview-1", time: "9:30pm", action: "Mix", note: nil, sortOrder: 1),
            ScheduleEntry(id: "s3", bakeId: "preview-1", time: "10:30am", action: "Shape", note: "Definitely over proofed", sortOrder: 2),
        ],
        photos: [],
        createdAt: "2026-02-13T00:00:00Z",
        updatedAt: "2026-02-13T00:00:00Z"
    )
}

struct Ingredient: Identifiable, Codable, Hashable {
    let id: String
    var bakeId: String
    var name: String
    var amount: String
    var note: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, amount, note
        case bakeId = "bake_id"
        case sortOrder = "sort_order"
    }
}

struct ScheduleEntry: Identifiable, Codable, Hashable {
    let id: String
    var bakeId: String
    var time: String
    var action: String
    var note: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, time, action, note
        case bakeId = "bake_id"
        case sortOrder = "sort_order"
    }
}

struct Photo: Identifiable, Codable, Hashable {
    let id: String
    var bakeId: String
    var r2Key: String
    var url: String?
    var caption: String?
    var sortOrder: Int
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, url, caption
        case bakeId = "bake_id"
        case r2Key = "r2_key"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}
