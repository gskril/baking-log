import SwiftUI

/// Slides a "No Internet Connection" bar in from the top edge whenever
/// connectivity drops. Applied to the root TabView and to sheets, which
/// present above it.
struct OfflineBannerModifier: ViewModifier {
    @ObservedObject private var network = NetworkMonitor.shared

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if !network.isOnline {
                    HStack(spacing: 6) {
                        Image(systemName: "wifi.slash")
                        Text("No Internet Connection")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.orange)
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
