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

        // Set the notification-center delegate before any notification can fire.
        ReminderManager.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-uiTestHost") {
                UITestHost()
            } else {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}
