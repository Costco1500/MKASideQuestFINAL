import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @State private var participants: [Participant] = []
    @State private var showingProfile = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand()
                    Text("Your next hangout starts here.").font(.title.bold())
                    Text("You choose what SideQuest sees.").foregroundStyle(.secondary)
                    if participants.isEmpty {
                        Button("Try Demo") { participants = DemoData.participants() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Start SideQuest") { showingProfile = true }.buttonStyle(.bordered)
                    } else {
                        Text("The group context").font(.headline)
                        ForEach(participants) { person in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(person.displayName).font(.headline)
                                Text("\(person.ageRange.label) · Up to $\(Int(person.maxBudget)) · \(person.approximateArea)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.questCard()
                        }
                    }
                }.padding(24)
            }.background(Color.questBackground)
                .sheet(isPresented: $showingProfile) {
                    NavigationStack {
                        ProfileSetupView(profile: Participant(availability: DemoData.range())) {
                            participants = [$0]; showingProfile = false
                        }
                    }
                }
        }.tint(.questAccent)
    }
}
