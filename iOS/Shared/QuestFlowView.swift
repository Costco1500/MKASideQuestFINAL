import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @State private var participants: [Participant] = []
    @State private var showingProfile = false
    @State private var messages: [ImportedMessage] = []
    @State private var plans: [PlanOption] = []
    @State private var source = "demo"
    @State private var loading = false
    @State private var errorMessage = ""
    @State private var isDemo = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand()
                    Text("Your next hangout starts here.").font(.title.bold())
                    Text("You choose what SideQuest sees.").foregroundStyle(.secondary)
                    if participants.isEmpty {
                        Button("Try Demo") {
                            isDemo = true
                            participants = DemoData.participants()
                            messages = MessageImport.parse(DemoData.conversation)
                            MessageImport.select(.all, in: &messages)
                        }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                        Button("Start SideQuest") { showingProfile = true }.buttonStyle(.bordered)
                    } else if !plans.isEmpty {
                        Text("Three ways to make it happen").font(.title2.bold())
                        Text(source == "demo" ? "Demo plans · works offline" : "Planned for your group").font(.caption)
                        ForEach(plans) { PlanCard(plan: $0) }
                    } else {
                        Text("The group context").font(.headline)
                        ForEach(participants) { person in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(person.displayName).font(.headline)
                                Text("\(person.ageRange.label) · Up to $\(Int(person.maxBudget)) · \(person.approximateArea)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }.questCard()
                        }
                        MessageImportView(messages: $messages)
                        let windows = AvailabilityEngine.sharedFreeWindows(participants, range: participants[0].availability)
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Shared free time", systemImage: "calendar").font(.headline)
                            if windows.isEmpty { Text("No shared 90-minute window. Adjust availability before planning.") }
                            ForEach(windows.indices, id: \.self) { index in
                                Text("\(windows[index].start.formatted(date: .abbreviated, time: .shortened)) – \(windows[index].end.formatted(date: .omitted, time: .shortened))")
                            }
                        }.questCard()
                    }
                }.padding(24)
            }.background(Color.questBackground)
                .safeAreaInset(edge: .bottom) {
                    if !participants.isEmpty && plans.isEmpty {
                        VStack {
                            if !errorMessage.isEmpty { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                            Button(loading ? "Finding your next SideQuest…" : "Analyze \(MessageImport.analysisMessages(messages).count) selected messages") {
                                loading = true
                                Task { @MainActor in
                                    defer { loading = false }
                                    do {
                                        let result = try await PlanGenerator.generate(PlanningRequest(participants: participants, messages: messages))
                                        plans = result.plans; source = result.source
                                        messages = []
                                    } catch { errorMessage = error.localizedDescription }
                                }
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(loading || MessageImport.analysisMessages(messages).isEmpty).accessibilityIdentifier("generatePlans")
                        }.padding().frame(maxWidth: .infinity).background(.ultraThinMaterial)
                    }
                }
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
