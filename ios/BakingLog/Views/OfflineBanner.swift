import SwiftUI

/// Floats a "No Internet Connection" capsule in from the top edge whenever
/// connectivity drops. An overlay rather than a safe-area inset so it never
/// reflows the navigation bar or tints the status bar. Applied to the root
/// TabView and to sheets, which present above it.
struct OfflineBannerModifier: ViewModifier {
    private let network = NetworkMonitor.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if !network.isOnline {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("No Internet Connection")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.orange, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: network.isOnline)
    }
}

extension View {
    func offlineBanner() -> some View {
        modifier(OfflineBannerModifier())
    }
}
