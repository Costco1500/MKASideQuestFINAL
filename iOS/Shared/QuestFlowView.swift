import SwiftUI
import SideQuestCore

struct QuestFlowView: View {
    @ObservedObject var store: QuestStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var calendarPlan: PlanOption?
    @State private var fullConversation = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        HStack {
                            QuestBrand()
                            Spacer(minLength: 4)
                        }.id("top")
                        QuestStepProgress(current: store.stage.step)
                        if !store.status.isEmpty { QuestStatusBanner(text: store.status) { store.status = "" } }
                        switch store.stage {
                        case .conversation: conversation
                        case .analyzing: analyzing
                        case .understanding: understanding
                        case .plans, .voting: plans
                        case .winner: winner
                        }
                    }.padding(20).padding(.bottom, 12)
                }.accessibilityIdentifier("questScroll")
                    .onChange(of: store.stage.step) { _, _ in proxy.scrollTo("top", anchor: .top) }
                    .onChange(of: store.stage) { _, stage in
                        if stage == .conversation || stage == .analyzing { proxy.scrollTo("top", anchor: .top) }
                        if stage == .conversation { fullConversation = false }
                    }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingAbout = true } label: {
                        QuestPill(text: "Offline prototype", systemImage: "sparkles", tint: .questAccent)
                    }.buttonStyle(.plain).accessibilityLabel("About this prototype")
                }
                #if DEBUG
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reset Demo", systemImage: "arrow.counterclockwise") { store.reset() }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .accessibilityLabel("Demo options")
                }
                #endif
            }
            .sheet(item: $calendarPlan) { plan in
                CalendarEventEditor(title: plan.title, start: plan.start, end: plan.end, area: plan.calendarLocation) { saved in
                    calendarPlan = nil
                    store.status = saved ? "It's on the calendar. See you there!" : "Your plan is still here whenever you're ready."
                }.ignoresSafeArea()
            }
            .sheet(isPresented: $showingAbout) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 22) {
                        QuestHero(title: "A little less planning.\nA lot more together.", subtitle: "A guided SideQuest prototype.")
                        Text("This walkthrough uses a fictional conversation, curated plans, and simulated friends' votes. No live AI analysis takes place.")
                        Text("Calendar and Messages actions are real. Maps opens a sample meetup point; no venue or booking is confirmed.")
                        Spacer()
                    }.padding(24).questScreen()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingAbout = false } } }
                }
            }
        }.questScreen()
            .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.9), value: store.stage)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.session.votes.count)
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Recent group chat").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                Text("Alex · Maya · Jake · Sarah").font(.subheadline).foregroundStyle(Color.questSecondary)
                HStack(spacing: -7) {
                    ForEach(store.session.participants) { ParticipantAvatar(name: $0.displayName, size: 34) }
                    Text("Thursday needs a plan.").font(.caption).foregroundStyle(Color.questSecondary).padding(.leading, 16)
                }.padding(.top, 4)
            }
            HStack {
                Text(fullConversation ? "THE WHOLE CONVERSATION" : "THE PART WHERE PLANS ALMOST HAPPEN")
                    .font(.system(.caption2, design: .rounded, weight: .bold)).foregroundStyle(Color.questSecondary)
                Spacer()
            }
            ForEach(fullConversation ? store.messages : Array(store.messages.suffix(22))) { message in
                chatBubble(message)
            }
            Button(fullConversation ? "Show recent messages" : "View all 38 messages") { fullConversation.toggle() }
                .buttonStyle(QuestSecondaryButtonStyle())
        }
    }
    private func chatBubble(_ message: ImportedMessage) -> some View {
        let alex = message.sender == "Alex"
        return HStack(alignment: .top, spacing: 10) {
            if !alex { ParticipantAvatar(name: message.sender, size: 30) }
            VStack(alignment: .leading, spacing: 5) {
                Text(message.sender).font(.system(.caption, design: .rounded, weight: .bold)).foregroundStyle(Color.questAccent)
                Text(message.text).font(.system(.body, design: .rounded)).fixedSize(horizontal: false, vertical: true)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(alex ? Color.questSoft : Color.questSurface, in: RoundedRectangle(cornerRadius: 21))
            .overlay(RoundedRectangle(cornerRadius: 21).stroke(Color.questBorder.opacity(0.7)))
            if alex { ParticipantAvatar(name: message.sender, size: 30) }
        }
        .padding(.leading, alex ? 26 : 0).padding(.trailing, alex ? 0 : 26)
        .accessibilityElement(children: .combine)
    }
    private var analyzing: some View {
        VStack(alignment: .center, spacing: 26) {
            ZStack {
                Circle().fill(Color.questSoft).frame(width: 132, height: 132)
                Image(systemName: "sparkles").font(.system(size: 50, weight: .medium)).foregroundStyle(Color.questAccent)
            }.accessibilityHidden(true)
            Text(store.analysisText).font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center).accessibilityIdentifier("analysisStatus")
            ProgressView().tint(Color.questAccent).controlSize(.large)
            Text("A little coordination.\nA whole evening together.")
                .font(.subheadline).foregroundStyle(Color.questSecondary).multilineTextAlignment(.center)
            Text("Simulated analysis · no data leaves this demo").font(.caption2).foregroundStyle(Color.questSecondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 48)
    }
    private var understanding: some View {
        VStack(alignment: .leading, spacing: 22) {
            QuestHero(title: "Got it.", subtitle: "Four friends. One free evening.", symbol: "person.3.fill")
            VStack(alignment: .leading, spacing: 18) {
                QuestSectionHeader(title: "What the group wants", subtitle: "The little details that make a plan feel right.", systemImage: "heart.text.clipboard.fill")
                ForEach(DemoConversation.insights.indices, id: \.self) { index in
                    let insight = DemoConversation.insights[index]
                    Label(insight.text, systemImage: insight.symbol)
                        .font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .foregroundStyle(Color.questText).padding(.vertical, 2)
                }
                Label("4 friends · everyone available", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.bold()).foregroundStyle(Color.questSuccess)
            }.questCard()
            DisclosureGroup {
                VStack(spacing: 14) {
                    ForEach(store.session.participants) { person in
                        HStack(alignment: .top, spacing: 12) {
                            ParticipantAvatar(name: person.displayName, ready: true)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(person.displayName).font(.system(.headline, design: .rounded))
                                Text(person.location?.displayArea ?? person.approximateArea).font(.caption).foregroundStyle(Color.questSecondary)
                                Text("Up to $\(Int(person.maxBudget)) · " + availability(for: person.id)).font(.caption)
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 6)
                    }
                }.padding(.top, 12)
            } label: {
                QuestSectionHeader(title: "Meet the group", subtitle: "Their profiles are already ready.", systemImage: "person.2.fill")
            }.questCard()
        }
    }
    private func availability(for id: String) -> String {
        ["alex": "After 6:30", "maya": "After 6", "jake": "After 6", "sarah": "5–10 PM"][id] ?? "Thursday evening"
    }
    private var plans: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Make it a group yes.").font(.system(.largeTitle, design: .rounded, weight: .heavy))
                Text("SideQuest found 3 plans").font(.headline).foregroundStyle(Color.questAccent)
                Text("Same free evening. Three ways to spend it together.").font(.subheadline).foregroundStyle(Color.questSecondary)
            }
            HStack(spacing: 12) {
                ParticipantAvatar(name: "Alex", size: 36)
                VStack(alignment: .leading) {
                    Text("You're voting as Alex").font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text("Down, Maybe, or Pass — then bring in the group.").font(.caption).foregroundStyle(Color.questSecondary)
                }
            }.questCard(padding: 14)
            ForEach(store.session.planOptions) { plan in
                PlanCard(plan: plan, onOpenMaps: { store.rememberMapsReturn() }) {
                    VStack(alignment: .leading, spacing: 14) {
                        whyItWorks(plan)
                        Divider()
                        VoteButtons(plan: plan, selected: store.session.votes.last { $0.participantId == "alex" && $0.planId == plan.id }?.value,
                                    disabled: store.busy) { store.vote(plan, value: $0) }
                        voteTally(plan)
                    }
                }
            }
        }
    }
    private func whyItWorks(_ plan: PlanOption) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(store.session.participants) { person in
                    HStack(alignment: .top, spacing: 10) {
                        ParticipantAvatar(name: person.displayName, size: 28)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.displayName).font(.caption.bold())
                            Text(plan.whyItWorks[person.id] ?? "").font(.caption).foregroundStyle(Color.questSecondary)
                        }
                    }
                }
                Label("Everyone is free after 6:30.", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(Color.questSuccess)
            }.padding(.top, 10)
        } label: {
            Label("Why it works for your friends", systemImage: "heart.fill").font(.system(.subheadline, design: .rounded, weight: .semibold))
        }.accessibilityIdentifier("why-\(plan.id)")
    }
    private func voteTally(_ plan: PlanOption) -> some View {
        let votes = store.session.votes.filter { $0.planId == plan.id }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ForEach(store.session.participants.filter { person in votes.contains { $0.participantId == person.id } }) { person in
                    let vote = votes.first { $0.participantId == person.id }!.value
                    VStack(spacing: 4) {
                        ParticipantAvatar(name: person.displayName, size: 30)
                        Text(vote.label).font(.caption2).foregroundStyle(Color.questSecondary)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(person.displayName): \(vote.label)")
                        .transition(.opacity)
                }
            }
            if !votes.isEmpty {
                Text("\(votes.filter { $0.value == .down }.count) Down · \(votes.filter { $0.value == .maybe }.count) Maybe · \(votes.filter { $0.value == .pass }.count) Pass")
                    .font(.caption).foregroundStyle(Color.questSecondary)
            }
        }
    }
    @ViewBuilder private var winner: some View {
        if let plan = store.session.winningPlan {
            QuestHero(title: "SideQuest set!", subtitle: plan.title, symbol: "party.popper.fill") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.start.formatted(.dateTime.weekday(.wide)) + " · " + CalendarBusyInterval(start: plan.start, end: plan.end).timeLabel)
                        .font(.headline).foregroundStyle(.white)
                    Text("~$\(Int(plan.estimatedCostPerPerson))/person · 4 friends").font(.subheadline).foregroundStyle(.white)
                }.padding(.top, 8)
            }
            Text("From “we should” to “see you there.”").font(.system(.title3, design: .rounded, weight: .bold))
            PlanCard(plan: plan, onOpenMaps: { store.rememberMapsReturn() }) {
                voteTally(plan)
                whyItWorks(plan)
            }
            Text("Everyone had a say. Now make it a memory.")
                .font(.caption).foregroundStyle(Color.questSecondary)
        }
    }
    @ViewBuilder private var actionBar: some View {
        VStack(spacing: 9) {
            switch store.stage {
            case .conversation:
                Button { store.analyze() } label: { Label("Analyze Recent Chat", systemImage: "sparkles") }
                    .buttonStyle(QuestPrimaryButtonStyle()).accessibilityIdentifier("analyzeChat")
                Text("A fictional chat. A very familiar problem.").font(.caption2).foregroundStyle(Color.questSecondary)
            case .analyzing:
                Text("Making room for everyone.").font(.caption).foregroundStyle(Color.questSecondary)
            case .understanding:
                Button { store.showPlans() } label: { Label("Show 3 plans", systemImage: "arrow.right") }
                    .buttonStyle(QuestPrimaryButtonStyle())
            case .plans:
                Button { store.simulateGroupVotes() } label: { Label("Simulate group votes", systemImage: "person.3.fill") }
                    .buttonStyle(QuestPrimaryButtonStyle()).disabled(!store.canSimulateVotes)
                Text(store.hasVoted ? "Maya, Jake, and Sarah join in on this device." : "Cast a vote as Alex to continue.")
                    .font(.caption2).foregroundStyle(Color.questSecondary)
            case .voting:
                HStack { ProgressView().tint(Color.questAccent); Text("\(store.respondingFriend) is voting…").font(.subheadline.bold()) }
                Text("Simulated group responses").font(.caption2).foregroundStyle(Color.questSecondary)
            case .winner:
                if let plan = store.session.winningPlan {
                    Button { calendarPlan = plan } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        .buttonStyle(QuestPrimaryButtonStyle())
                    if store.insert != nil {
                        Button { store.share() } label: { Label("Share Final Plan", systemImage: "bubble.left.and.text.bubble.right.fill") }
                            .buttonStyle(QuestSecondaryButtonStyle())
                    } else {
                        ShareLink(item: "\(plan.title)\n\(plan.start.formatted(date: .abbreviated, time: .shortened))\n~$\(Int(plan.estimatedCostPerPerson))/person\n\(plan.calendarLocation)\nPlanned together with SideQuest.") {
                            Label("Share Final Plan", systemImage: "square.and.arrow.up")
                        }.buttonStyle(QuestSecondaryButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity).padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
        .background(Color.questBackground)
    }
}
