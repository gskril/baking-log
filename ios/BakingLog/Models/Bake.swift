import Foundation

struct Bake: Identifiable, Codable, Hashable {
    let id: String
    var title: String?
    var bakeDate: String
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
        case ingredientCount = "ingredient_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayDate: String {
        Formatters.displayDay(bakeDate)
    }

    static let example = Bake(
        id: "preview-1",
        title: "Sourdough Loaf",
        bakeDate: "2026-02-13",
        ingredients: [
            Ingredient(id: "i1", bakeId: "preview-1", name: "Starter", amountValue: 90, unit: "g", note: nil, sortOrder: 0),
            Ingredient(id: "i2", bakeId: "preview-1", name: "Water", amountValue: 325, unit: "g", note: nil, sortOrder: 1),
            Ingredient(id: "i3", bakeId: "preview-1", name: "Salt", amountValue: 10, unit: "g", note: nil, sortOrder: 2),
            Ingredient(id: "i4", bakeId: "preview-1", name: "Whole Wheat", amountValue: 45, unit: "g", note: nil, sortOrder: 3),
            Ingredient(id: "i5", bakeId: "preview-1", name: "Rye", amountValue: 45, unit: "g", note: nil, sortOrder: 4),
            Ingredient(id: "i6", bakeId: "preview-1", name: "White Flour", amountValue: 360, unit: "g", note: "half ap, half bread", sortOrder: 5),
        ],
        ingredientCount: nil,
        notes: nil,
        schedule: [
            ScheduleEntry(id: "s1", bakeId: "preview-1", occursAt: "2026-02-12T14:45:00", action: "Feed starter", note: nil, sortOrder: 0),
            ScheduleEntry(id: "s2", bakeId: "preview-1", occursAt: "2026-02-12T21:30:00", action: "Mix", note: nil, sortOrder: 1),
            ScheduleEntry(id: "s3", bakeId: "preview-1", occursAt: "2026-02-13T10:30:00", action: "Shape", note: "Definitely over proofed", sortOrder: 2),
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
    var amountValue: Double?
    var unit: String?
    var note: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, unit, note
        case bakeId = "bake_id"
        case amountValue = "amount_value"
        case sortOrder = "sort_order"
    }

    var displayAmount: String {
        Formatters.displayAmount(value: amountValue, unit: unit)
    }
}

struct ScheduleEntry: Identifiable, Codable, Hashable {
    let id: String
    var bakeId: String
    /// Local wall-clock ISO 8601 ("yyyy-MM-ddTHH:mm:ss"), no timezone.
    var occursAt: String?
    var action: String
    var note: String?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, action, note
        case bakeId = "bake_id"
        case occursAt = "occurs_at"
        case sortOrder = "sort_order"
    }

    var date: Date? {
        occursAt.flatMap(Formatters.parseDateTime)
    }
}

struct Photo: Identifiable, Codable, Hashable {
    let id: String
    var bakeId: String
    var caption: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, caption
        case bakeId = "bake_id"
        case createdAt = "created_at"
    }
}
