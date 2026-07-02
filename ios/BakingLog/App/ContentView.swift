import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                BakeListView()
            }
            .tabItem {
                Label("Bakes", systemImage: "oven")
            }

            NavigationStack {
                CalculatorView()
            }
            // Immediate dismissal only suits the calculator's single-line
            // number fields; on bake screens it makes multi-line notes
            // impossible to edit (any scroll hides the keyboard).
            .scrollDismissesKeyboard(.immediately)
            .tabItem {
                Label("Calculator", systemImage: "percent")
            }
        }
        .offlineBanner()
    }
}
