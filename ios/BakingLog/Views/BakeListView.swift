import SwiftUI

struct BakeListView: View {
    @StateObject private var vm = BakeListViewModel()
    @State private var showingNewBake = false

    var body: some View {
        Group {
            if vm.isLoading && vm.bakes.isEmpty {
                ProgressView()
            } else if let error = vm.error, vm.bakes.isEmpty {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "wifi.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await vm.load() }
                    }
                }
            } else if vm.bakes.isEmpty {
                ContentUnavailableView {
                    Label("No Bakes Yet", systemImage: "oven")
                } description: {
                    Text("Tap + to log your first bake")
                }
            } else {
                List {
                    ForEach(vm.bakes) { bake in
                        NavigationLink(value: bake) {
                            BakeRow(bake: bake)
                        }
                    }
                    .onDelete { offsets in
                        Task { await vm.delete(at: offsets) }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Baking Log")
        .navigationDestination(for: Bake.self) { bake in
            BakeDetailView(bakeId: bake.id)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingNewBake = true
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showingNewBake) {
            BakeEditView {
                showingNewBake = false
                Task { await vm.load() }
            }
        }
        .refreshable {
            await vm.load()
        }
        .task {
            await vm.load()
        }
    }
}

struct BakeRow: View {
    let bake: Bake

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bake.title)
                .font(.headline)
            Text(bake.displayDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let ingredients = bake.ingredients, !ingredients.isEmpty {
                let count = ingredients.components(separatedBy: "\n").count
                Text("\(count) ingredient\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
