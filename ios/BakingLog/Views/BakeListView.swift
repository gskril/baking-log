import SwiftUI

struct BakeListView: View {
    @StateObject private var vm = BakeListViewModel()
    @ObservedObject private var syncManager = SyncManager.shared
    @State private var showingNewBake = false

    var body: some View {
        Group {
            if vm.isLoading && vm.bakes.isEmpty && syncManager.pendingBakes.isEmpty {
                ProgressView()
            } else if let error = vm.error, vm.bakes.isEmpty, syncManager.pendingBakes.isEmpty {
                ContentUnavailableView {
                    Label("Connection Error", systemImage: "wifi.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") {
                        Task { await vm.load() }
                    }
                }
            } else if vm.bakes.isEmpty && syncManager.pendingBakes.isEmpty {
                ContentUnavailableView {
                    Label("No Bakes Yet", systemImage: "oven")
                } description: {
                    Text("Tap + to log your first bake")
                }
            } else {
                List {
                    // Pending bakes waiting to sync
                    if !syncManager.pendingBakes.isEmpty {
                        Section {
                            ForEach(syncManager.pendingBakes) { pending in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(pending.payload.title)
                                            .font(.headline)
                                        Text(pending.displayDate)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if syncManager.isSyncing {
                                        ProgressView()
                                    } else {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                            .foregroundStyle(.orange)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .onDelete { offsets in
                                for i in offsets {
                                    syncManager.removePending(id: syncManager.pendingBakes[i].id)
                                }
                            }
                        } header: {
                            HStack {
                                Text("Pending Sync")
                                if syncManager.isSyncing {
                                    Text("Syncing...")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    // Server bakes
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
                HStack(spacing: 16) {
                    // Push webhooks button
                    Button {
                        Task { await vm.pushWebhooks() }
                    } label: {
                        if vm.isPushing {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane")
                        }
                    }
                    .disabled(vm.isPushing)

                    Button {
                        showingNewBake = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: 12) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }

                    if !syncManager.isOnline {
                        Image(systemName: "wifi.slash")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
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
            if !syncManager.pendingBakes.isEmpty {
                await syncManager.syncPending()
            }
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
