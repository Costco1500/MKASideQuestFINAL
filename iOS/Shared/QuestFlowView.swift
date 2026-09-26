import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @ObservedObject var store: QuestStore
    @State private var expectedPeople = 2
    @State private var showingProfile = false
    @State private var showingSettings = false
    @State private var showingHoursCheck = false
    @State private var calendarPlan: PlanOption?
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand().id("top")
                    if !store.status.isEmpty { QuestStatusBanner(text: store.status) { store.status = "" } }
                    if store.pendingImportCount > 0 { pendingImportCard }
                    if let session = store.session { sessionContent(session) } else { startContent }
                    if store.session == nil && !store.messages.isEmpty { MessageImportView(store: store) }
                }.padding(20).padding(.bottom, 12)
            }.accessibilityIdentifier("questScroll")
                // New plans, a winner, or a new session start at the top instead of the old scroll position.
                .onChange(of: stageKey) { _, _ in proxy.scrollTo("top", anchor: .top) }
            }
                .safeAreaInset(edge: .bottom) {
                    if let session = store.session, session.planOptions.isEmpty, store.isOwner {
                        Button { store.generate() } label: {
                            Label(store.busy ? "Finding your next SideQuest…" : (store.isPreloadedConversation && !store.choosingMessages ? "Analyze Recent Chat" : "Analyze \(MessageImport.analysisMessages(store.messages).count) Messages"),
                                  systemImage: "wand.and.stars")
                        }
                        .buttonStyle(QuestPrimaryButtonStyle())
                        .disabled(!store.canGenerate).accessibilityIdentifier("generatePlans")
                        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8).frame(maxWidth: .infinity)
                        .background(LinearGradient(colors: [Color.questBackground.opacity(0), .questBackground, .questBackground], startPoint: .top, endPoint: .bottom))
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button { showingSettings = true } label: { Image(systemName: "gearshape.fill") }.accessibilityLabel("Settings") }
                    if store.session != nil { ToolbarItem(placement: .topBarLeading) { Button("New") { store.reset() } } }
                }
                .sheet(isPresented: $showingProfile) {
                    NavigationStack {
                        ProfileSetupView(profile: ownProfile, saveTitle: "Done — share my context") { store.saveProfile($0); showingProfile = false }
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showingProfile = false } } }
                    }
                }
                .sheet(isPresented: $showingSettings) { NavigationStack { SettingsView() } }
                .sheet(isPresented: $showingHoursCheck) {
                    NavigationStack { PlaceHoursCheckView(options: hoursCheckOptions, center: groupCenter, area: groupArea) }
                }
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

    // MARK: Start

    private var pendingImportCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestSectionHeader(title: "Conversation ready", subtitle: "\(store.pendingImportCount) messages imported", systemImage: "tray.and.arrow.down.fill")
            if store.session?.planOptions.isEmpty == false {
                Text("Start a new SideQuest to review this conversation.").font(.subheadline)
                Button("New SideQuest") { store.reset(); store.reviewPendingImport() }.buttonStyle(QuestPrimaryButtonStyle())
            } else {
                Button("Review Messages") { store.reviewPendingImport() }.buttonStyle(QuestPrimaryButtonStyle())
            }
            Button("Discard", role: .destructive) { store.discardPendingImport() }.buttonStyle(QuestSecondaryButtonStyle())
        }.questCard()
    }

    @ViewBuilder private var startContent: some View {
        if let invitation = store.invitation {
            QuestHero(title: "Join this SideQuest", subtitle: "Your group is planning something. Add your time and budget so the plan works for you too.", symbol: "person.3.fill")
            VStack(alignment: .leading, spacing: 14) {
                QuestSectionHeader(title: "Only your own info",
                                   subtitle: "Shared with this group at \(invitation.serverURL.host ?? "their server"). Joining restarts planning so your constraints are included.",
                                   systemImage: "lock.fill")
                Button { store.expand?(); showingProfile = true } label: { Label("Join SideQuest", systemImage: "hand.wave.fill") }
                    .buttonStyle(QuestPrimaryButtonStyle())
            }.questCard()
        } else {
            QuestHero(title: "Your next hangout starts here.", subtitle: "Turn the group chat into a plan everyone's actually down for.")
            Label("You choose what SideQuest sees.", systemImage: "hand.raised.fill").font(.subheadline).foregroundStyle(Color.questSecondary)
            VStack(alignment: .leading, spacing: 16) {
                QuestSectionHeader(title: "Plan with this chat", subtitle: "Send an invite, everyone adds their time and budget, then you vote on three plans.",
                                   systemImage: "bubble.left.and.bubble.right.fill")
                Stepper(value: $expectedPeople, in: 1...12) {
                    HStack(spacing: -8) {
                        ForEach(0..<min(expectedPeople, 5), id: \.self) { index in
                            Image(systemName: "person.fill").font(.system(size: 13, weight: .bold)).foregroundStyle(Color.questText)
                                .frame(width: 32, height: 32)
                                .background([Color.questClay, .questAmber, .questSuccess, .questAccent][index % 4].opacity(0.28), in: Circle())
                                .overlay(Circle().stroke(Color.questSurface, lineWidth: 2))
                                .accessibilityHidden(true)
                        }
                        Text("\(expectedPeople) people, including you").font(.system(.subheadline, design: .rounded, weight: .semibold)).padding(.leading, 16)
                    }
                }
                Button { store.startSession(expectedParticipantCount: expectedPeople) } label: {
                    Label(store.busy ? "Starting…" : "Start SideQuest", systemImage: "paperplane.fill")
                }
                .buttonStyle(QuestPrimaryButtonStyle()).disabled(store.busy)
                Label(serverCaption, systemImage: "server.rack").font(.caption).foregroundStyle(Color.questSecondary)
            }.questCard()
            if store.needsServer { ServerSetupCard { showingSettings = true } }
            VStack(alignment: .leading, spacing: 14) {
                QuestSectionHeader(title: "Just looking around?", subtitle: "Walk through a sample group chat with four friends. Works offline.", systemImage: "sparkles")
                Button("Try Demo") { store.startDemo() }.buttonStyle(QuestSecondaryButtonStyle())
            }.questCard()
            howItWorks
        }
    }

    private var serverCaption: String {
        let saved = QuestPreferences.server.trimmingCharacters(in: .whitespaces)
        if !saved.isEmpty { return "Group server: " + (URL(string: saved)?.host ?? saved) }
        if !QuestPreferences.effectiveServer.isEmpty { return "Using the demo server on this Mac. Run python3 backend/server.py first." }
        return "Shared sessions need your group's server. Add it in Settings."
    }

    private var howItWorks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How it works").font(.system(.headline, design: .rounded, weight: .bold))
            ForEach(Array([("paperplane.fill", "Invite the chat", "One card, sent by you."),
                           ("calendar.badge.clock", "Everyone adds their time", "SideQuest finds the best times from each calendar."),
                           ("hand.thumbsup.fill", "Vote on three plans", "Real places, checked against their opening hours.")].enumerated()), id: \.offset) { _, step in
                HStack(spacing: 12) {
                    Image(systemName: step.0).foregroundStyle(Color.questAccent).frame(width: 32, height: 32)
                        .background(Color.questSoft, in: Circle()).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(step.1).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text(step.2).font(.caption).foregroundStyle(Color.questSecondary)
                    }
                }
            }
        }.questCard()
    }

    // MARK: Session

    private var stageKey: String {
        guard let session = store.session else { return "start" }
        return session.id + "-\(step(for: session))" + (store.isPreloadedConversation ? "-chat" : "")
    }

    private func step(for session: SideQuestSession) -> Int {
        if session.winningPlan != nil { return 4 }
        if !session.planOptions.isEmpty { return 3 }
        if session.everyoneReady { return 2 }
        return session.participants.isEmpty ? 0 : 1
    }

    @ViewBuilder private func sessionContent(_ session: SideQuestSession) -> some View {
        QuestStepProgress(current: step(for: session))
        HStack {
            if store.isDemo { QuestPill(text: "Demo", systemImage: "sparkles", tint: .questAccent) }
            else { QuestPill(text: "Shared session · \(session.participants.count) joined", systemImage: "person.2.fill") }
            Spacer()
            if !store.isDemo {
                Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(QuestSecondaryButtonStyle()).accessibilityLabel("Refresh session")
            }
        }
        if let winner = session.winningPlan { winnerContent(winner, session: session) }
        else if !session.planOptions.isEmpty { pollContent(session) }
        else if store.isPreloadedConversation {
            groupTimesCard(session)
            MessageImportView(store: store)
        } else { waitingContent(session) }
    }

    @ViewBuilder private func winnerContent(_ winner: PlanOption, session: SideQuestSession) -> some View {
        QuestHero(title: "SideQuest set 🎉", subtitle: "\(session.participants.count) people · chosen by the group", symbol: "party.popper.fill")
        PlanCard(plan: winner, onOpenMaps: { store.rememberMapsReturn() })
        Button { calendarPlan = winner } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
            .buttonStyle(QuestPrimaryButtonStyle())
        Text("Choose a calendar and confirm in Apple's event editor.").font(.caption).foregroundStyle(Color.questSecondary)
        Button { store.share() } label: { Label("Share winning plan", systemImage: "square.and.arrow.up") }
            .buttonStyle(QuestSecondaryButtonStyle())
    }

    @ViewBuilder private func pollContent(_ session: SideQuestSession) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Make it a group yes.").font(.system(.largeTitle, design: .rounded, weight: .heavy))
            Text(session.source == "demo" ? "Three demo suggestions. Confirm prices before you go." : "Three plans shaped around your group.")
                .font(.subheadline).foregroundStyle(Color.questSecondary)
        }
        if store.isDemo {
            HStack(spacing: 12) {
                ParticipantAvatar(name: session.participants.first { $0.id == store.demoParticipantID }?.displayName ?? "?", size: 36)
                Text("Voting as").font(.subheadline).foregroundStyle(Color.questSecondary)
                Picker("Demo voter", selection: $store.demoParticipantID) { ForEach(session.participants) { Text($0.displayName).tag($0.id) } }
                    .pickerStyle(.menu).tint(.questAccent)
                Spacer(minLength: 0)
            }.questCard(padding: 14)
        }
        ForEach(session.planOptions) { plan in
            PlanCard(plan: plan, onOpenMaps: { store.rememberMapsReturn() }) {
                VStack(alignment: .leading, spacing: 12) {
                    Divider().overlay(Color.questBorder)
                    if let fit = plan.whyItWorks[store.participantID] {
                        Label("For you: \(fit)", systemImage: "person.fill.checkmark").font(.caption).foregroundStyle(Color.questSecondary)
                    }
                    VoteButtons(plan: plan, selected: session.votes.last { $0.participantId == store.participantID && $0.planId == plan.id }?.value,
                                disabled: store.busy) { store.vote(plan, value: $0) }
                    voteTally(plan, session: session)
                }
            }
        }
        Button { showingHoursCheck = true } label: { Label("Is it open? Check another place", systemImage: "door.left.hand.open") }
            .buttonStyle(QuestSecondaryButtonStyle())
        Button { store.share() } label: { Label("Insert poll into Messages", systemImage: "bubble.left.and.text.bubble.right.fill") }
            .buttonStyle(QuestPrimaryButtonStyle())
        Text("The card goes into the compose field. You choose when to send.").font(.caption).foregroundStyle(Color.questSecondary)
        if store.isOwner {
            Button { store.finalize() } label: { Label("Set the SideQuest", systemImage: "flag.checkered") }
                .buttonStyle(QuestSecondaryButtonStyle())
                .disabled(VoteEngine.winner(in: session) == nil || store.busy).accessibilityIdentifier("finalize")
        }
    }

    private func voteTally(_ plan: PlanOption, session: SideQuestSession) -> some View {
        let votes = session.votes.filter { $0.planId == plan.id }
        let voters = session.participants.filter { person in votes.contains { $0.participantId == person.id } }
        return HStack(spacing: 10) {
            HStack(spacing: -8) { ForEach(voters.prefix(5)) { ParticipantAvatar(name: $0.displayName, size: 26) } }
            Text("\(votes.count) votes").font(.caption.bold())
            Text(VoteValue.allCases.map { value in "\(votes.filter { $0.value == value }.count) \(value.rawValue)" }.joined(separator: " · "))
                .font(.caption).foregroundStyle(Color.questSecondary)
        }
    }

    @ViewBuilder private func waitingContent(_ session: SideQuestSession) -> some View {
        let expected = session.expectedParticipantCount ?? session.participants.count
        let readyIDs = Set(session.readyParticipantIds ?? [])
        Text("Bring everyone into the plan.").font(.system(.title, design: .rounded, weight: .heavy))
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ReadinessRing(ready: session.readyCount, expected: expected)
                VStack(alignment: .leading, spacing: 4) {
                    Label("\(session.readyCount) of \(expected) people Done", systemImage: session.everyoneReady ? "checkmark.circle.fill" : "person.2")
                        .font(.headline).accessibilityIdentifier("sessionReadiness")
                    Text(session.everyoneReady ? "Everyone is ready. The organizer can analyze the selected messages." : "Waiting for everyone to add their profile, availability, and tap Done.")
                        .font(.subheadline).foregroundStyle(Color.questSecondary)
                }
            }
            ForEach(session.participants) { person in
                HStack(spacing: 12) {
                    ParticipantAvatar(name: person.displayName, ready: readyIDs.contains(person.id))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName + (person.id == store.participantID ? " (you)" : "")).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        Text("\(person.ageRange.label) · $\(Int(person.maxBudget)) max · \(person.approximateArea)").font(.caption).foregroundStyle(Color.questSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(readyIDs.contains(person.id) ? "Done" : "Waiting").font(.caption.bold())
                        .foregroundStyle(readyIDs.contains(person.id) ? Color.questSuccess : .questSecondary)
                }
            }
            ForEach(0..<max(0, expected - session.participants.count), id: \.self) { _ in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.plus").font(.title2).foregroundStyle(Color.questSecondary)
                        .frame(width: 40, height: 40).accessibilityHidden(true)
                    Text("Invite pending").font(.subheadline).foregroundStyle(Color.questSecondary)
                }
            }
            if let budget = Participant.groupBudget(session.participants) {
                QuestPill(text: "Group budget: up to $\(Int(budget))/person", systemImage: "dollarsign.circle.fill")
            }
        }.questCard()
        if !store.isDemo {
            Button { store.share() } label: { Label("Invite group to contribute", systemImage: "paperplane.fill") }
                .buttonStyle(QuestPrimaryButtonStyle())
            Button { showingProfile = true } label: {
                Label(session.participants.contains { $0.id == store.participantID } ? "Edit my context" : "Add my profile & availability", systemImage: "person.crop.circle.fill")
            }
            .buttonStyle(QuestSecondaryButtonStyle()).accessibilityIdentifier("myContext")
            Text("Send the invitation to the whole group. Each person opens it and taps Done with their own information.").font(.caption).foregroundStyle(Color.questSecondary)
        }
        groupTimesCard(session)
        Button { showingHoursCheck = true } label: { Label("Is it open? Check a place", systemImage: "door.left.hand.open") }
            .buttonStyle(QuestSecondaryButtonStyle())
        if store.isOwner { MessageImportView(store: store) }
        else { Text("You're Done. Once everyone is ready, the organizer will generate plans here for your group to vote on.").questCard() }
    }

    private func groupTimesCard(_ session: SideQuestSession) -> some View {
        BestTimesCard(title: "Best times for the group",
                      subtitle: "Ranked from everyone's calendars and windows. Plans start with the top pick.",
                      slots: groupSlots(session),
                      emptyMessage: session.participants.isEmpty
                        ? "Best times show up here as people add their availability."
                        : "No shared 90-minute window yet. Edit availability before planning.")
    }

    private func groupSlots(_ session: SideQuestSession) -> [RankedTimeSlot] {
        guard let first = session.participants.first else { return [] }
        return AvailabilityEngine.bestTimes(session.participants, range: first.availability, now: Date())
    }

    // MARK: Opening-hours check

    private var hoursCheckOptions: [PlaceHoursCheckView.TimeOption] {
        var options: [PlaceHoursCheckView.TimeOption] = []
        if let session = store.session {
            for plan in session.planOptions {
                let window = CalendarBusyInterval(start: plan.start, end: plan.end)
                options.append(.init(id: "plan-" + plan.id, label: "\(plan.title) · \(window.dayLabel) \(plan.start.formatted(date: .omitted, time: .shortened))", window: window))
            }
            for (index, slot) in groupSlots(session).enumerated() {
                options.append(.init(id: "slot-\(index)", label: (index == 0 ? "Best time · " : "") + slot.window.dayLabel + " " + slot.window.timeLabel, window: slot.window))
            }
        }
        if options.isEmpty {
            let evening = CalendarBusyInterval.nextEvening()
            let window = CalendarBusyInterval(start: evening.start.addingTimeInterval(7200), end: evening.start.addingTimeInterval(4 * 3600))
            options.append(.init(id: "evening", label: window.dayLabel + " " + window.timeLabel, window: window))
        }
        return options
    }

    private var groupCenter: ParticipantLocation? {
        var people = store.session?.participants ?? []
        if let index = people.firstIndex(where: { $0.id == store.participantID }), let exact = QuestPreferences.profile.location { people[index].location = exact }
        return ParticipantLocation.center(of: people.compactMap(\.location)) ?? QuestPreferences.profile.location
    }

    private var groupArea: String {
        store.session?.participants.first?.approximateArea ?? QuestPreferences.profile.approximateArea
    }
}
