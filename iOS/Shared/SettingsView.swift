import SwiftUI
import SideQuestCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var server = QuestPreferences.server
    @State private var status = ""
    var body: some View {
        Form {
            Section("Shared-session server") {
                TextField("https://your-sidequest-api.example", text: $server).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                Text("Everyone in a shared session uses the same HTTPS backend. The API key stays on that server.").font(.caption)
                #if targetEnvironment(simulator)
                Button("Use local demo server") { server = "http://127.0.0.1:8787" }
                #endif
                Button("Save server") {
                    guard let url = URL(string: server), (try? APIClient(baseURL: url)) != nil else { status = "Enter a valid HTTPS URL."; return }
                    QuestPreferences.server = server; status = "Server saved."
                }
                if !status.isEmpty { Text(status).font(.caption) }
            }
            Section("Privacy") {
                Text("Imported conversations stay in memory and are cleared after planning. Only selected messages are sent. Calendars contribute busy times, never titles or notes. You can enter your area manually.")
                Text("Shared sessions expire after seven days. Session invitations let people with the card join and view shared context.").font(.caption)
            }
        }.navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
