import Foundation

enum AppGroup {
    static let identifier = "group.com.bakinglog.shared"

    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: identifier) ?? .standard
    }
}
