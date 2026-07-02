import SwiftUI

/// Nudges a freshly inserted row into view above the keyboard.
///
/// Two passes: one after the row insertion settles, one after the keyboard
/// finishes its frame change — on device those animations run longer than in
/// the simulator, and a single early scroll lands short. When the first pass
/// already landed right, the second is a visual no-op.
///
/// `BakeEditUITests` sleeps past the final pass before asserting row
/// visibility — keep its `Thread.sleep` values ahead of `passDelays`.
enum KeyboardReveal {
    static let passDelays: [TimeInterval] = [0.45, 0.9]

    @MainActor
    static func reveal(_ id: some Hashable, in proxy: ScrollViewProxy) {
        for delay in passDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }
}
