import SwiftUI

struct WebhookSettingsView: View {
    @StateObject private var viewModel = WebhookSettingsViewModel()
    @State private var showingAddSheet = false
    @State private var newURL = ""
    @State private var newSecret = ""

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else if viewModel.webhooks.isEmpty {
                Text("No webhooks registered")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.webhooks) { webhook in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(webhook.url)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        if webhook.secret != nil {
                            Text("Signed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await viewModel.delete(at: offsets) }
                }
            }

            if let error = viewModel.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Webhooks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newURL = ""
                    newSecret = ""
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            addWebhookSheet
        }
        .task {
            await viewModel.load()
        }
    }

    private var addWebhookSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com/webhook", text: $newURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("URL")
                }

                Section {
                    TextField("Optional", text: $newSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Secret")
                } footer: {
                    Text("Used for HMAC-SHA256 signature verification")
                }
            }
            .navigationTitle("Add Webhook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingAddSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let secret = newSecret.isEmpty ? nil : newSecret
                        Task {
                            await viewModel.add(url: newURL, secret: secret)
                            showingAddSheet = false
                        }
                    }
                    .disabled(newURL.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
