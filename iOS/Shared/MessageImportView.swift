import SwiftUI
import PhotosUI
import SideQuestCore

struct MessageImportView: View {
    @ObservedObject var store: QuestStore
    @State private var selectedPhotos: [PhotosPickerItem] = []
    private var senderNames: [String] {
        Array(Set((store.session?.participants.map(\.displayName) ?? []) + store.messages.map(\.sender)))
            .filter { !$0.isEmpty && $0 != "Unknown" }.sorted() + ["Unknown"]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.isPreloadedConversation {
                Text("Recent group chat").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Alex, Maya, Jake & Sarah · sample conversation").font(.subheadline).foregroundStyle(Color.questSecondary)
                if !store.choosingMessages {
                    Button("Choose Messages") { store.choosingMessages = true }.buttonStyle(QuestSecondaryButtonStyle())
                }
            }
            if !store.isPreloadedConversation || store.choosingMessages {
            Text("Bring the conversation").font(.title2.bold())
            Text("Take screenshots of the messages you want to use, then choose them in order. Text recognition happens on your device.")
                .font(.subheadline).foregroundStyle(Color.questSecondary)
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 10, selectionBehavior: .ordered, matching: .images) {
                Label("Scan Recent Chat", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
            }.buttonStyle(QuestPrimaryButtonStyle()).controlSize(.large).disabled(store.isReading || store.busy)
                .onChange(of: selectedPhotos) { _, items in
                    guard !items.isEmpty else { return }
                    store.importPhotos(items); selectedPhotos = []
                }
            Text("Choose up to 10 screenshots. Only the message text you select below is shared for planning.").font(.caption).foregroundStyle(Color.questSecondary)
            if store.isDemo {
                Button("Scan demo screenshots") { store.readChat() }.disabled(store.isReading || store.busy)
                Text("Demo profiles are already Done. These sample screenshots use the same on-device recognition as your photos.").font(.caption).foregroundStyle(Color.questSecondary)
            }
            if store.isReading { HStack { ProgressView(); Text("Reading screenshots on your device…").font(.subheadline) } }
            }
            if !store.messages.isEmpty {
                if !store.isPreloadedConversation || store.choosingMessages {
                Text("Check what SideQuest found").font(.headline)
                Text("Tap a name to correct the sender. Tap a message to select it.").font(.caption).foregroundStyle(Color.questSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 8) {
                        Button("Last 10") { select(.latest10) }
                        Button("Last 25") { select(.latest25) }
                        Button("Last 50") { select(.latest50) }
                        Button("All") { select(.all) }
                        Button("Clear") { select(.clear) }
                }.buttonStyle(QuestSecondaryButtonStyle()).disabled(store.isReading || store.busy)
                let count = store.messages.filter(\.isSelected).count
                Text("\(count) messages selected").font(.caption).accessibilityIdentifier("selectionCount")
                if count > 50 { Text("Only the latest 50 unique selections will be analyzed.").font(.caption).foregroundStyle(Color.questSecondary) }
                }
                ForEach($store.messages) { $message in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            Text(String(message.sender.prefix(1))).font(.system(.caption, design: .rounded, weight: .bold))
                                .frame(width: 32, height: 32).background(Color.questSoft, in: Circle()).accessibilityHidden(true)
                        Menu {
                            ForEach(senderNames, id: \.self) { name in Button(name) { message.sender = name } }
                        } label: {
                            Label(message.sender, systemImage: "chevron.down").font(.caption.bold())
                        }.frame(minHeight: 44).accessibilityLabel(message.sender).accessibilityIdentifier("messageSender")
                        }
                        Button { message.isSelected.toggle() } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: message.isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(message.isSelected ? Color.questAccent : .questSecondary)
                                Text(message.text).font(.body).foregroundStyle(Color.questText).frame(maxWidth: .infinity, alignment: .leading)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityValue(message.isSelected ? "Selected" : "Not selected")
                    }.padding(18).background(message.isSelected ? Color.questRaised : .questSurface, in: RoundedRectangle(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(message.isSelected ? Color.questClay : .questBorder, lineWidth: 1.5))
                        .shadow(color: .questShadow.opacity(message.isSelected ? 0.05 : 0), radius: 16, y: 6)
                        .disabled(store.isReading || store.busy)
                }
                Button("Clear Imported Messages", role: .destructive) { store.stopReading(); store.messages = []; store.status = "" }
            }
        }
    }
    private func select(_ selection: MessageImport.Selection) { MessageImport.select(selection, in: &store.messages) }
}
