import SwiftUI

struct SettingsView: View {
    @AppStorage("api_base_url", store: AppGroup.sharedDefaults)
    private var apiBaseURL = "https://baking-log.gregskril.workers.dev"

    @AppStorage("api_key", store: AppGroup.sharedDefaults)
    private var apiKey = ""

    /// Non-blocking warning when the API URL doesn't look like an http(s) URL.
    private var apiURLWarning: String? {
        let trimmed = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let url = URL(string: trimmed, encodingInvalidCharacters: false),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            return "This doesn't look like a valid http(s) URL"
        }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("API URL", text: $apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit {
                        apiBaseURL = apiBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
            } header: {
                Text("Server")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let apiURLWarning {
                        Label(apiURLWarning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    Text("The URL of your Cloudflare Worker (e.g., https://baking-log.you.workers.dev)")
                }
            }

            Section {
                SecureField("API Key (optional)", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Authentication")
            } footer: {
                Text("Only needed if you set API_KEY in your worker config")
            }

            Section {
                NavigationLink("Webhooks") {
                    WebhookSettingsView()
                }
            } footer: {
                Text("Trigger external site rebuilds when you push bake updates")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
