import SwiftUI

struct OnboardingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    QuestBrand()
                    Text("Less planning.\nMore hanging out.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("Turn the group chat into your next good memory.").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Find SideQuest in Messages", systemImage: "message.fill").font(.headline)
                        Text("Open a conversation, tap +, then choose SideQuest. Your group plans together right there.")
                        Label("You choose what SideQuest sees.", systemImage: "hand.raised.fill").font(.subheadline)
                    }.questCard()
                }.padding(24)
            }.background(Color.questBackground)
        }.tint(.questAccent)
    }
}
