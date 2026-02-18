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
            .tabItem {
                Label("Calculator", systemImage: "percent")
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }
}
