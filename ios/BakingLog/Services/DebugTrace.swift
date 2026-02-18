import Foundation
import OSLog

enum DebugTrace {
    private static let logger = Logger(subsystem: "com.bakinglog.app", category: "trace")

    static func log(_ message: String) {
        logger.log("\(message, privacy: .public)")
        print("[DebugTrace] \(message)")
    }
}
