import SwiftUI

struct SettingsView: View {
    @AppStorage("api_base_url", store: AppGroup.sharedDefaults)
    private var apiBaseURL = "http://localhost:8787"

    @AppStorage("api_key", store: AppGroup.sharedDefaults)
    private var apiKey = ""

    var body: some View {
        Form {
            Section {
                TextField("API URL", text: $apiBaseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } header: {
                Text("Server")
            } footer: {
                Text("The URL of your Cloudflare Worker (e.g., https://baking-log.you.workers.dev)")
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
