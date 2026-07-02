import Foundation
import Network
import Observation

/// Status-only connectivity monitor. Drives the offline banner — it does
/// not queue or retry anything.
@Observable @MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isOnline = true

    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.bakinglog.networkmonitor"))
    }
}
