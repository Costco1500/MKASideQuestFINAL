import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @ObservedObject var store: QuestStore
    @State private var expectedPeople = 2
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var calendarPlan: PlanOption?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand()
                    if store.pendingImportCount > 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Conversation ready").font(.headline)
                            Text("\(store.pendingImportCount) messages imported")
                            if store.session?.planOptions.isEmpty == false {
                                Text("Start a new SideQuest to review this conversation.").font(.subheadline)
                                Button("New SideQuest") { store.reset(); store.reviewPendingImport() }.buttonStyle(QuestPrimaryButtonStyle())
                            } else {
                                Button("Review Messages") { store.reviewPendingImport() }.buttonStyle(QuestPrimaryButtonStyle())
                            }
                            Button("Discard", role: .destructive) { store.discardPendingImport() }.buttonStyle(QuestSecondaryButtonStyle())
                        }.questCard()
                    }
                    if let session = store.session { sessionContent(session) }
                    else {
                        Text("Your next hangout starts here.").font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("You choose what SideQuest sees.").foregroundStyle(Color.questSecondary)
                        if let invitation = store.invitation {
                            Text("Join this SideQuest").font(.headline)
                            Text("Share your own context with this group at \(invitation.serverURL.host ?? ""). Joining restarts planning so your constraints are included.").font(.subheadline)
                            Button("Join SideQuest") { store.expand?(); showingProfile = true }.buttonStyle(QuestPrimaryButtonStyle())
                        } else {
                            Button("Try Demo") { store.startDemo() }.buttonStyle(QuestPrimaryButtonStyle()).controlSize(.large)
                            Stepper("\(expectedPeople) people, including you", value: $expectedPeople, in: 1...12)
                            Button("Start SideQuest") { store.startSession(expectedParticipantCount: expectedPeople) }.buttonStyle(QuestSecondaryButtonStyle()).disabled(store.busy)
                            Text("Start a session and send the invitation first. Everyone adds their profile and taps Done before plans can be made.").font(.caption)
                            Text("An offline demo is ready. For shared sessions, set your group's server in Settings.").font(.caption).foregroundStyle(Color.questSecondary)
                        }
                    }
                    if store.session == nil && !store.messages.isEmpty { MessageImportView(store: store) }
                    if !store.status.isEmpty { Text(store.status).font(.subheadline).foregroundStyle(Color.questSecondary).accessibilityIdentifier("status") }
                }.padding(20)
            }.accessibilityIdentifier("questScroll").background(Color.questBackground)
                .safeAreaInset(edge: .bottom) {
                    if let session = store.session, session.planOptions.isEmpty, store.isOwner {
                        Button(store.busy ? "Finding your next SideQuest…" : (store.isPreloadedConversation && !store.choosingMessages ? "Analyze Recent Chat" : "Analyze \(MessageImport.analysisMessages(store.messages).count) Messages")) { store.generate() }
                            .buttonStyle(QuestPrimaryButtonStyle()).controlSize(.large)
                            .disabled(!store.canGenerate).accessibilityIdentifier("generatePlans")
                            .padding().frame(maxWidth: .infinity).background(Color.questBackground)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Settings") }
                    if store.session != nil { ToolbarItem(placement: .topBarLeading) { Button("New") { store.reset() } } }
                }
                .sheet(isPresented: $showingProfile) {
                    NavigationStack {
                        ProfileSetupView(profile: ownProfile, saveTitle: "Done — share my context") { store.saveProfile($0); showingProfile = false }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingProfile = false } } }
                    }
                }
                .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
                .sheet(item: $calendarPlan) { plan in
                    CalendarEventEditor(title: plan.title, start: plan.start, end: plan.end, area: plan.calendarLocation) { saved in
                        calendarPlan = nil
                        store.status = saved ? "Added to your calendar." : "Calendar closed without saving."
                    }.ignoresSafeArea()
                }
                .onChange(of: store.chatSize, initial: true) { _, count in
                    if let count { expectedPeople = min(12, max(1, count)) }
                }
                .task(id: store.session?.id) {
                    guard !store.isDemo, store.membership != nil else { return }
                    while !Task.isCancelled {
                        await store.refresh(silent: true)
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
        }.questScreen()
    }
    private var ownProfile: Participant { store.session?.participants.first { $0.id == store.participantID } ?? QuestPreferences.profile }
    @ViewBuilder private func sessionContent(_ session: SideQuestSession) -> some View {
        if store.isDemo { Label("Demo", systemImage: "sparkles").font(.caption2).foregroundStyle(Color.questSecondary) }
        else {
            Label("Shared session · \(session.participants.count) joined", systemImage: "person.2.fill").font(.caption)
            Button("Refresh session") { Task { await store.refresh() } }.buttonStyle(QuestSecondaryButtonStyle())
        }
        if let winner = session.winningPlan {
            Text("SideQuest set 🎉").font(.largeTitle.bold())
            PlanCard(plan: winner, onOpenMaps: { store.rememberMapsReturn() })
            Text("\(session.participants.count) people · chosen by the group").font(.subheadline)
            Button("Add to Calendar") { calendarPlan = winner }.buttonStyle(QuestPrimaryButtonStyle())
            Text("Choose a calendar and confirm in Apple's event editor.").font(.caption).foregroundStyle(Color.questSecondary)
            Button("Share winning plan") { store.share() }.buttonStyle(QuestPrimaryButtonStyle())
        } else if !session.planOptions.isEmpty {
            Text("Make it a group yes.").font(.system(.largeTitle, design: .rounded, weight: .bold))
            Text(session.source == "demo" ? "Three demo suggestions. Confirm prices and availability." : "Three plans shaped around your group.").font(.subheadline).foregroundStyle(Color.questSecondary)
            if store.isDemo {
                Picker("Demo voter", selection: $store.demoParticipantID) { ForEach(session.participants) { Text($0.displayName).tag($0.id) } }.pickerStyle(.menu)
            }
            ForEach(session.planOptions) { plan in
                VStack(spacing: 8) {
                    PlanCard(plan: plan, onOpenMaps: { store.rememberMapsReturn() })
                    if let fit = plan.whyItWorks[store.participantID] { Text("For you: \(fit)").font(.caption).foregroundStyle(Color.questSecondary) }
                    HStack {
                        ForEach(VoteValue.allCases, id: \.self) { value in
                            let selected = session.votes.last { $0.participantId == store.participantID && $0.planId == plan.id }?.value == value
                            Button(value.label) { store.vote(plan, value: value) }.buttonStyle(QuestSecondaryButtonStyle(selected: selected))
                                .accessibilityIdentifier("vote-\(plan.id)-\(value.rawValue)")
                                .accessibilityValue(selected ? "Selected" : "Not selected").disabled(store.busy)
                        }
                    }
                    Text("\(session.votes.filter { $0.planId == plan.id }.count) votes").font(.caption)
                }
            }
            Button("Insert poll into Messages") { store.share() }.buttonStyle(QuestPrimaryButtonStyle())
            Text("The card goes into the compose field. You choose when to send.").font(.caption)
            if store.isOwner {
                Button("Set the SideQuest") { store.finalize() }.buttonStyle(QuestSecondaryButtonStyle())
                    .disabled(VoteEngine.winner(in: session) == nil || store.busy).accessibilityIdentifier("finalize")
            }
        } else if store.isPreloadedConversation {
            MessageImportView(store: store)
        } else {
            Text("Bring everyone into the plan.").font(.title2.bold())
            VStack(alignment: .leading, spacing: 8) {
                Label("\(session.readyCount) of \(session.expectedParticipantCount ?? session.participants.count) people Done", systemImage: session.everyoneReady ? "checkmark.circle.fill" : "person.2")
                    .font(.headline).accessibilityIdentifier("sessionReadiness")
                Text(session.everyoneReady ? "Everyone is ready. The organizer can analyze the selected messages." : "Waiting for everyone to add their profile, availability, and tap Done.").font(.subheadline)
            }.questCard()
            DisclosureGroup("\(session.participants.count) people · up to $\(Int(Participant.groupBudget(session.participants) ?? 0))/person") {
                ForEach(session.participants) { person in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.displayName + ((session.readyParticipantIds ?? []).contains(person.id) ? " · Done" : " · Waiting")).font(.headline)
                        Text("\(person.ageRange.label) · $\(Int(person.maxBudget)) max · \(person.approximateArea)").font(.caption)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
            }.questCard()
            if !store.isDemo {
                Button("Invite group to contribute") { store.share() }.buttonStyle(QuestPrimaryButtonStyle())
                Button(session.participants.contains { $0.id == store.participantID } ? "Edit my context" : "Add my profile & availability") { showingProfile = true }.buttonStyle(QuestSecondaryButtonStyle()).accessibilityIdentifier("myContext")
                Text("Send the invitation to the whole group. Each person opens it and taps Done with their own information.").font(.caption)
            }
            if store.isOwner { MessageImportView(store: store) }
            else { Text("You’re Done. Once everyone is ready, the organizer will generate plans here for your group to vote on.") }
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
