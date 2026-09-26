import SwiftUI
import SideQuestCore

struct MessageImportView: View {
    @Binding var messages: [ImportedMessage]
    @State private var pastedText = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose the context").font(.title2.bold())
            Text("Paste a conversation, then select what may be analyzed. SideQuest cannot read your Messages history.")
                .font(.subheadline).foregroundStyle(.secondary)
            TextEditor(text: $pastedText).frame(height: 110).padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Paste Conversation")
            Button("Import pasted messages") {
                messages = MessageImport.parse(pastedText); pastedText = ""
            }.buttonStyle(.bordered).disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !messages.isEmpty {
                ViewThatFits {
                    HStack { selectionButtons }
                    VStack(alignment: .leading) { selectionButtons }
                }.buttonStyle(.bordered).controlSize(.small)
                Text("\(messages.filter(\.isSelected).count) selected · latest 50 unique selections used per plan")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($messages) { $message in
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
                }
                Button("Clear Imported Messages", role: .destructive) { messages = []; pastedText = "" }
            }
        }
    }
    @ViewBuilder private var selectionButtons: some View {
        Button("Select All") { MessageImport.select(.all, in: &messages) }
        Button("Clear") { MessageImport.select(.clear, in: &messages) }
        Button("Select Latest 50") { MessageImport.select(.latest50, in: &messages) }
    }
}
