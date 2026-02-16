import Foundation

struct Bake: Identifiable, Codable, Hashable {
    let id: String
    var title: String
    var bakeDate: String
    var ingredients: String?
    var notes: String?
    var schedule: [ScheduleEntry]?
    var photos: [Photo]?
    let createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, title, ingredients, notes, schedule, photos
        case bakeDate = "bake_date"
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
        ingredients: "90g starter\n325g water\n10g salt\n45g whole wheat\n45g rye\n360g white flour (half ap, half bread)",
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
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, url, caption
        case bakeId = "bake_id"
        case r2Key = "r2_key"
        case createdAt = "created_at"
    }
}
