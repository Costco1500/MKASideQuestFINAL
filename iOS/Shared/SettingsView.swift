import SwiftUI
import SideQuestCore

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var server = QuestPreferences.server
    @State private var status = ""
    @State private var chatScript = QuestPreferences.demoChatScript ?? DemoData.conversation
    @State private var chatScriptStatus = ""
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
            }.listRowBackground(Color.questSurface)
            Section("Demo chat script") {
                TextEditor(text: $chatScript).scrollContentBackground(.hidden).frame(minHeight: 160).font(.callout).autocorrectionDisabled()
                    .accessibilityLabel("Demo chat script")
                Text("One \"Name: message\" per line. Demo screenshots are rendered from these messages and scanned on-device. Use the demo names so plans and votes line up: \(DemoData.participants().map(\.displayName).joined(separator: ", ")).")
                    .font(.caption)
                Button("Save script") {
                    QuestPreferences.demoChatScript = chatScript
                    chatScriptStatus = "Script saved · \(DemoData.chatScript(chatScript).count) messages."
                }
                Button("Reset to default") {
                    QuestPreferences.demoChatScript = nil; chatScript = DemoData.conversation; chatScriptStatus = "Default script restored."
                }
                if !chatScriptStatus.isEmpty { Text(chatScriptStatus).font(.caption) }
            }.listRowBackground(Color.questSurface)
            Section("Privacy") {
                Text("Only selected messages are sent for planning. Reviewed conversations are cleared afterward. Shared screenshots are kept only as extracted text until you review or discard it. Calendars contribute busy times, never titles or notes. Exact user location stays on-device.")
                Text("Shared sessions expire after seven days. Session invitations let people with the card join and view shared context.").font(.caption)
            }.listRowBackground(Color.questSurface)
        }.buttonStyle(QuestSecondaryButtonStyle()).scrollContentBackground(.hidden).questScreen().navigationTitle("Settings").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
