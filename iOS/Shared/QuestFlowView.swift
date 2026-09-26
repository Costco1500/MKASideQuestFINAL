import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @ObservedObject var store: QuestStore
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var calendarPlan: PlanOption?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand()
                    if let session = store.session { sessionContent(session) }
                    else {
                        Text("Your next hangout starts here.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("You choose what SideQuest sees.").foregroundStyle(.secondary)
                        if let invitation = store.invitation {
                            Text("Join this SideQuest").font(.headline)
                            Text("Share your own context with this group at \(invitation.serverURL.host ?? ""). Joining restarts planning so your constraints are included.").font(.subheadline)
                            Button("Join SideQuest") { store.expand?(); showingProfile = true }.buttonStyle(.borderedProminent)
                        } else {
                            Button("Try Demo") { store.startDemo() }.buttonStyle(.borderedProminent).controlSize(.large)
                            Button("Start SideQuest") { store.expand?(); showingProfile = true }.buttonStyle(.bordered)
                            Text("An offline demo is ready. For shared sessions, set your group's server in Settings.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if !store.status.isEmpty { Text(store.status).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("status") }
                }.padding(20)
            }.background(Color.questBackground)
                .safeAreaInset(edge: .bottom) {
                    if let session = store.session, session.planOptions.isEmpty, store.isOwner {
                        Button(store.busy ? "Finding your next SideQuest…" : "Analyze \(MessageImport.analysisMessages(store.messages).count) selected messages") { store.generate() }
                            .buttonStyle(.borderedProminent).controlSize(.large)
                            .disabled(store.busy || MessageImport.analysisMessages(store.messages).isEmpty).accessibilityIdentifier("generatePlans")
                            .padding().frame(maxWidth: .infinity).background(.ultraThinMaterial)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                    if store.session != nil { ToolbarItem(placement: .topBarLeading) { Button("New") { store.reset() } } }
                }
                .sheet(isPresented: $showingProfile) {
                    NavigationStack {
                        ProfileSetupView(profile: ownProfile) { store.saveProfile($0); showingProfile = false }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingProfile = false } } }
                    }
                }
                .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
                .sheet(item: $calendarPlan) { plan in
                    CalendarEventEditor(title: plan.title, start: plan.start, end: plan.end, area: plan.area) { saved in
                        calendarPlan = nil
                        store.status = saved ? "Added to your calendar." : "Calendar closed without saving."
                    }.ignoresSafeArea()
                }
                .task(id: store.session?.id) {
                    guard !store.isDemo, store.membership != nil else { return }
                    while !Task.isCancelled {
                        await store.refresh(silent: true)
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
        }.tint(.questAccent)
    }
    private var ownProfile: Participant { store.session?.participants.first { $0.id == store.participantID } ?? QuestPreferences.profile }
    @ViewBuilder private func sessionContent(_ session: SideQuestSession) -> some View {
        if store.isDemo { Label("Offline demo · votes stay on this device", systemImage: "airplane").font(.caption).foregroundStyle(.secondary) }
        else {
            Label("Shared session · \(session.participants.count) joined", systemImage: "person.2.fill").font(.caption)
            Button("Refresh session") { Task { await store.refresh() } }
        }
        if let winner = session.winningPlan {
            Text("SideQuest set 🎉").font(.largeTitle.bold())
            PlanCard(plan: winner)
            Text("\(session.participants.count) people · chosen by the group").font(.subheadline)
            Button("Add to Calendar") { calendarPlan = winner }.buttonStyle(.borderedProminent)
            Text("Choose a calendar and confirm in Apple's event editor.").font(.caption).foregroundStyle(.secondary)
            Button("Share winning plan") { store.share() }.buttonStyle(.borderedProminent)
        } else if !session.planOptions.isEmpty {
            Text("Make it a group yes.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(session.source == "demo" ? "Three demo suggestions. Confirm prices and availability." : "Three plans shaped around your group.").font(.subheadline).foregroundStyle(.secondary)
            if store.isDemo {
                Picker("Demo voter", selection: $store.demoParticipantID) { ForEach(session.participants) { Text($0.displayName).tag($0.id) } }.pickerStyle(.menu)
            }
            ForEach(session.planOptions) { plan in
                VStack(spacing: 8) {
                    PlanCard(plan: plan)
                    if let fit = plan.whyItWorks[store.participantID] { Text("For you: \(fit)").font(.caption).foregroundStyle(.secondary) }
                    HStack {
                        ForEach(VoteValue.allCases, id: \.self) { value in
                            let selected = session.votes.last { $0.participantId == store.participantID && $0.planId == plan.id }?.value == value
                            Button(value.label) { store.vote(plan, value: value) }.buttonStyle(.bordered).tint(selected ? .questAccent : .gray)
                                .accessibilityIdentifier("vote-\(plan.id)-\(value.rawValue)")
                                .accessibilityValue(selected ? "Selected" : "Not selected").disabled(store.busy)
                        }
                    }
                    Text("\(session.votes.filter { $0.planId == plan.id }.count) votes").font(.caption)
                }
            }
            Button("Insert poll into Messages") { store.share() }.buttonStyle(.borderedProminent)
            Text("The card goes into the compose field. You choose when to send.").font(.caption)
            if store.isOwner {
                Button("Set the SideQuest") { store.finalize() }.buttonStyle(.bordered)
                    .disabled(VoteEngine.winner(in: session) == nil || store.busy).accessibilityIdentifier("finalize")
            }
        } else {
            Text("Bring everyone into the plan.").font(.title2.bold())
            DisclosureGroup("\(session.participants.count) people · up to $\(Int(Participant.groupBudget(session.participants) ?? 0))/person") {
                ForEach(session.participants) { person in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.displayName).font(.headline)
                        Text("\(person.ageRange.label) · $\(Int(person.maxBudget)) max · \(person.approximateArea)").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }.questCard()
            if !store.isDemo {
                Button("Invite group to contribute") { store.share() }.buttonStyle(.borderedProminent)
                Button("Edit my context") { showingProfile = true }
                Text("Each person joins with their own information. Wait for everyone before generating.").font(.caption)
            }
            if store.isOwner { MessageImportView(messages: $store.messages) }
            else { Text("Your context is shared. The organizer will generate plans when everyone has joined.") }
            let request = PlanningRequest(participants: session.participants, messages: [])
            VStack(alignment: .leading, spacing: 8) {
                Label("Shared free time", systemImage: "calendar").font(.headline)
                if request.candidateTimeWindows.isEmpty { Text("No shared 90-minute window. Edit availability before planning.") }
                ForEach(request.candidateTimeWindows.indices, id: \.self) { index in
                    Text(request.candidateTimeWindows[index].start.formatted(date: .abbreviated, time: .shortened) + " – " + request.candidateTimeWindows[index].end.formatted(date: .omitted, time: .shortened))
                }
            }.questCard()
        }
    }
}
