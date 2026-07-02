import SwiftUI

@main
struct BakingLogApp: App {
    init() {
        // Offline mode was removed; clear any queue files it left in
        // Documents (they held raw JPEG data and could be several MB).
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            for name in ["pending_bakes.json", "pending_updates.json", "pending_photo_uploads.json"] {
                try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains("-datePickerRepro") {
                DebugPickerRepro()
            } else {
                ContentView()
            }
        }
    }
}
