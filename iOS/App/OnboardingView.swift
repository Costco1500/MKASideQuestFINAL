import SwiftUI
import SideQuestCore

struct OnboardingView: View {
    @StateObject private var preview = QuestStore()
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    QuestBrand()
                    QuestHero(title: "Less planning.\nMore hanging out.", subtitle: "Turn the group chat into your next good memory.", symbol: "sun.horizon.fill")
                    VStack(alignment: .leading, spacing: 12) {
                        QuestSectionHeader(title: "Before your first plan", subtitle: "Save your budget, area, and free times once. Check your calendar to see your best times.",
                                           systemImage: "person.crop.circle.badge.checkmark")
                        NavigationLink {
                            ProfileSetupView(profile: QuestPreferences.profile) { QuestPreferences.profile = $0 }
                        } label: { Label("Set up my profile", systemImage: "person.fill") }
                            .buttonStyle(QuestPrimaryButtonStyle())
                        NavigationLink {
                            QuestFlowView(store: preview).onAppear { if preview.session == nil { preview.startDemo() } }
                        } label: { Text("Try Demo") }
                            .buttonStyle(QuestSecondaryButtonStyle())
                    }.questCard()
                    VStack(alignment: .leading, spacing: 16) {
                        QuestSectionHeader(title: "Find SideQuest in Messages", subtitle: "Your group plans together right inside the chat.", systemImage: "message.fill")
                        ForEach(Array(["Open a group conversation.", "Tap +, then choose SideQuest.", "Tap Start SideQuest and send the invite."].enumerated()), id: \.offset) { index, step in
                            HStack(spacing: 12) {
                                Text("\(index + 1)").font(.system(.subheadline, design: .rounded, weight: .heavy))
                                    .foregroundStyle(Color(uiColor: QuestPalette.primaryText))
                                    .frame(width: 28, height: 28).background(.questPrimary, in: Circle())
                                Text(step).font(.subheadline)
                            }
                        }
                        Label("You choose what SideQuest sees.", systemImage: "hand.raised.fill").font(.caption).foregroundStyle(Color.questSecondary)
                    }.questCard()
                    NavigationLink { SettingsView() } label: {
                        HStack {
                            Label("Settings", systemImage: "gearshape.fill").font(.system(.subheadline, design: .rounded, weight: .semibold))
                            Spacer()
                            Text(QuestPreferences.server.isEmpty ? "Group server not set" : (URL(string: QuestPreferences.server)?.host ?? ""))
                                .font(.caption).foregroundStyle(Color.questSecondary)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Color.questSecondary)
                        }.questCard(padding: 16)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                        .accessibilityValue(QuestPreferences.server.isEmpty ? "Group server not set" : (URL(string: QuestPreferences.server)?.host ?? ""))
                }.padding(22)
            }
        }.questScreen()
    }
}
