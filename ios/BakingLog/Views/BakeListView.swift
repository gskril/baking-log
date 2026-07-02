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
            BakeDetailView(bakeId: bake.id, initialTitle: bake.title)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 8) {
                    // Push webhooks button
                    Button {
                        Task { await vm.pushWebhooks() }
                    } label: {
                        if vm.isPushing {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane")
                                .padding(8)
                                .contentShape(Rectangle())
                        }
                    }
                    .disabled(vm.isPushing)

                    Button {
                        showingNewBake = true
                    } label: {
                        Image(systemName: "plus")
                            .padding(8)
                            .contentShape(Rectangle())
                    }
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
        .onChange(of: vm.pushResult) {
            // Clear push result after 3 seconds
            if vm.pushResult != nil {
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    vm.pushResult = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let result = vm.pushResult {
                Text(result)
                    .font(.footnote.bold())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut, value: vm.pushResult)
            }
        }
    }
}

struct BakeRow: View {
    let bake: Bake

    private var ingredientCountText: String? {
        // Prefer structured ingredient count from list endpoint
        if let count = bake.ingredientCount, count > 0 {
            return "\(count) ingredient\(count == 1 ? "" : "s")"
        }
        // Fallback: count from structured array (detail endpoint)
        if let ingredients = bake.ingredients, !ingredients.isEmpty {
            return "\(ingredients.count) ingredient\(ingredients.count == 1 ? "" : "s")"
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bake.title ?? "Untitled Bake")
                .font(.headline)
            Text(bake.displayDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let text = ingredientCountText {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
