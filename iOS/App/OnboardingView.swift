import SwiftUI
import SideQuestCore

struct OnboardingView: View {
    @StateObject private var preview = QuestStore()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    QuestBrand()
                    Text("Less planning.\nMore hanging out.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Turn the group chat into your next good memory.").foregroundStyle(Color.questSecondary)
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Find SideQuest in Messages", systemImage: "message.fill").font(.headline)
                        Text("Open a conversation, tap +, then choose SideQuest. Your group plans together right there.")
                        Label("You choose what SideQuest sees.", systemImage: "hand.raised.fill").font(.subheadline)
                    }.questCard()
                    NavigationLink("Set up my profile") {
                        ProfileSetupView(profile: QuestPreferences.profile) { QuestPreferences.profile = $0 }
                    }.buttonStyle(QuestPrimaryButtonStyle())
                    NavigationLink("Try Demo") { QuestFlowView(store: preview).onAppear { if preview.session == nil { preview.startDemo() } } }.buttonStyle(QuestSecondaryButtonStyle())
                    NavigationLink("Settings") { SettingsView() }
                }.padding(24)
            }.background(Color.questBackground)
        }.questScreen()
    }
}
