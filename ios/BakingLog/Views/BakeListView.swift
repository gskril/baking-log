import SwiftUI

struct BakeListView: View {
    @State private var vm = BakeListViewModel()
    private let network = NetworkMonitor.shared
    @State private var showingNewBake = false
    @State private var pushToastClearTask: Task<Void, Never>?

    private var isShowingError: Binding<Bool> {
        Binding {
            vm.error != nil && !vm.bakes.isEmpty
        } set: { isPresented in
            if !isPresented {
                vm.error = nil
            }
        }
    }

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
                        .task {
                            // Infinite scroll: fetch the next page when the
                            // last loaded row becomes visible.
                            if bake.id == vm.bakes.last?.id {
                                await vm.loadMore()
                            }
                        }
                    }
                    .onDelete { offsets in
                        Task { await vm.delete(at: offsets) }
                    }

                    if vm.isLoadingMore {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
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
                    .accessibilityLabel("Push Webhooks")

                    Button {
                        showingNewBake = true
                    } label: {
                        Image(systemName: "plus")
                            .padding(8)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("New Bake")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
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
        .alert("Something Went Wrong", isPresented: isShowingError, presenting: vm.error) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error)
        }
        .task {
            await vm.load()
        }
        // Recover automatically when connectivity returns instead of leaving
        // the error state up until a manual retry.
        .onChange(of: network.isOnline) { _, online in
            if online && vm.bakes.isEmpty {
                Task { await vm.load() }
            }
        }
        .onChange(of: vm.pushResult) {
            // Clear push result after 3 seconds. Cancel any in-flight clear
            // task first so an earlier toast's timer can't dismiss a newer one.
            pushToastClearTask?.cancel()
            if vm.pushResult != nil {
                pushToastClearTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    vm.pushResult = nil
                }
            }
        }
        .overlay(alignment: .bottom) {
            ZStack {
                if let result = vm.pushResult {
                    Text(result)
                        .font(.footnote.bold())
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut, value: vm.pushResult)
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
