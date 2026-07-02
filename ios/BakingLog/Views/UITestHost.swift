import SwiftUI

#if DEBUG
// Network-free UI-test host (see BakeEditUITests). Launched with `-uiTestHost`
// instead of ContentView; presents the real BakeEditView in a sheet, as the
// app does, with a fixture that needs no API connection.
struct UITestHost: View {
    @State private var showingEdit = false

    // No ingredients/photos so the schedule section is on screen when the
    // sheet auto-presents.
    private static let fixture = Bake(
        id: "repro-1",
        title: "Repro Loaf",
        bakeDate: "2026-06-27",
        ingredients: [],
        ingredientCount: nil,
        notes: nil,
        schedule: [
            ScheduleEntry(id: "s1", bakeId: "repro-1", occursAt: "2026-06-27T13:00:00", action: "Mix", note: nil, sortOrder: 0),
            ScheduleEntry(id: "s2", bakeId: "repro-1", occursAt: "2026-06-28T17:20:00", action: "Bake", note: nil, sortOrder: 1),
        ],
        photos: [],
        createdAt: "2026-06-27T00:00:00Z",
        updatedAt: "2026-06-27T00:00:00Z"
    )

    var body: some View {
        Text("UI-test host")
            .task {
                try? await Task.sleep(for: .seconds(1))
                showingEdit = true
            }
            .sheet(isPresented: $showingEdit) {
                BakeEditView(existing: Self.fixture) {}
            }
    }
}
#endif
