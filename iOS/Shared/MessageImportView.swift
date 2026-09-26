import SwiftUI
import SideQuestCore

struct MessageImportView: View {
    @ObservedObject var store: QuestStore
    @State private var pastedText = ""
    @State private var showingManualEntry = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the context").font(.title2.bold())
            if store.isDemo {
                Text("SideQuest reads your group's recent messages to find plans.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button { store.readChat() } label: {
                    Label(store.chatSize == nil ? "Load demo chat" : "Read this chat", systemImage: "text.magnifyingglass")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(store.isReading)
                    .accessibilityIdentifier("readChat")
                if let size = store.chatSize, size > 2 {
                    Label("Group chat · \(size) people", systemImage: "person.3.fill").font(.caption).foregroundStyle(.secondary)
                }
                if store.isReading {
                    HStack(spacing: 10) { ProgressView(); Text("Reading messages…").font(.subheadline) }
                }
                DisclosureGroup("Add messages manually", isExpanded: $showingManualEntry) { manualEntry.padding(.top, 8) }
                    .font(.subheadline)
            } else {
                Text("Paste a conversation, then select what may be analyzed. SideQuest cannot read your Messages history.")
                    .font(.subheadline).foregroundStyle(.secondary)
                manualEntry
            }
            if !store.messages.isEmpty {
                if !store.isReading {
                    ViewThatFits {
                        HStack { selectionButtons }
                        VStack(alignment: .leading) { selectionButtons }
                    }.buttonStyle(.bordered).controlSize(.small)
                    Text("\(store.messages.filter(\.isSelected).count) selected · latest 50 unique selections used per plan")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($store.messages) { $message in
                    Button { message.isSelected.toggle() } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: message.isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(message.isSelected ? Color.questAccent : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.sender).font(.caption.bold())
                                Text(message.text).font(.body).foregroundStyle(.primary)
                            }
                            Spacer(minLength: 0)
                        }.padding(14).background(.background, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain).accessibilityValue(message.isSelected ? "Selected" : "Not selected")
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if !store.isReading {
                    Button("Clear Imported Messages", role: .destructive) { store.messages = []; pastedText = ""; store.status = "" }
                }
            }
        }
    }
    @ViewBuilder private var manualEntry: some View {
        TextEditor(text: $pastedText).frame(height: 110).padding(8)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityLabel("Paste Conversation")
        Button("Import pasted messages") {
            store.stopReading(); store.messages = MessageImport.parse(pastedText); pastedText = ""
        }.buttonStyle(.bordered).disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    @ViewBuilder private var selectionButtons: some View {
        Button("Select All") { MessageImport.select(.all, in: &store.messages) }
        Button("Clear") { MessageImport.select(.clear, in: &store.messages) }
        Button("Select Latest 50") { MessageImport.select(.latest50, in: &store.messages) }
    }
}
