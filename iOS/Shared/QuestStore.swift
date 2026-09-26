import SwiftUI
import SideQuestCore

enum DemoStage: String {
    case conversation, analyzing, understanding, plans, voting, winner
    var step: Int {
        switch self {
        case .conversation, .analyzing: return 0
        case .understanding: return 1
        case .plans, .voting: return 2
        case .winner: return 3
        }
    }
}

/// This build is a local prototype: no server, imported data, or model calls.
@MainActor final class QuestStore: ObservableObject {
    @Published private(set) var session: SideQuestSession
    @Published private(set) var messages = DemoConversation.messages
    @Published private(set) var stage: DemoStage = .conversation
    @Published private(set) var analysisText = ""
    @Published private(set) var respondingFriend = ""
    @Published var status = ""
    var insert: ((SideQuestSession, SessionLink) -> Void)?
    var expand: (() -> Void)?
    private var task: Task<Void, Never>?
    private let phaseDelay: Duration
    private let voteDelay: Duration
    private let defaults = UserDefaults(suiteName: "group.com.sidequest.shared") ?? .standard
    var busy: Bool { stage == .analyzing || stage == .voting }
    var hasVoted: Bool { session.votes.contains { $0.participantId == "alex" } }
    var canSimulateVotes: Bool { stage == .plans && hasVoted }
    var link: SessionLink {
        SessionLink(sessionId: session.id, inviteToken: String(repeating: "d", count: 43),
                    serverURL: URL(string: "https://demo.sidequest.invalid")!, isDemo: true)
    }

    init(phaseDelay: Duration = .milliseconds(600), voteDelay: Duration = .milliseconds(350)) {
        self.phaseDelay = phaseDelay; self.voteDelay = voteDelay
        // The fixture uses a valid upcoming Thursday, with no external inputs.
        session = try! SideQuestSession.demo()
        session.planOptions = []
    }
    func analyze() {
        guard stage == .conversation else { return }
        expand?(); status = ""; stage = .analyzing
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for text in ["Reading the group…", "Finding what works for everyone…", "Putting the pieces together…"] {
                    analysisText = text
                    try await Task.sleep(for: phaseDelay)
                }
                try Task.checkCancellation()
                guard let request = session.context else { return }
                session.planOptions = try DemoPlanner.plans(for: request)
                analysisText = "Got it."
                stage = .understanding
            } catch is CancellationError { }
            catch { reset(); status = "Let's try that again." }
        }
    }
    func showPlans() {
        guard stage == .understanding else { return }
        stage = .plans
    }
    func vote(_ plan: PlanOption, value: VoteValue) {
        guard stage == .plans, session.planOptions.contains(where: { $0.id == plan.id }) else { return }
        session.votes.removeAll { $0.participantId == "alex" && $0.planId == plan.id }
        session.votes.append(Vote(participantId: "alex", planId: plan.id, value: value))
    }
    func simulateGroupVotes() {
        guard canSimulateVotes else { return }
        // Unrated options are Maybe; preserve every explicit vote Alex made.
        for plan in session.planOptions where !session.votes.contains(where: { $0.participantId == "alex" && $0.planId == plan.id }) {
            session.votes.append(Vote(participantId: "alex", planId: plan.id, value: .maybe))
        }
        session.votes.removeAll { $0.participantId != "alex" }
        stage = .voting; respondingFriend = "Maya"
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for person in session.participants where person.id != "alex" {
                    respondingFriend = person.displayName
                    try await Task.sleep(for: voteDelay)
                    try Task.checkCancellation()
                    session.votes += DemoConversation.votes(for: person.id, plans: session.planOptions)
                }
                try await Task.sleep(for: voteDelay)
                try Task.checkCancellation()
                session.winningPlanId = VoteEngine.winner(in: session)?.id
                stage = .winner; persistDemo()
            } catch { }
        }
    }
    func reset() {
        task?.cancel(); task = nil
        defaults.removeObject(forKey: "demo-maps-return")
        session = try! SideQuestSession.demo(); session.planOptions = []
        messages = DemoConversation.messages
        stage = .conversation; analysisText = ""; respondingFriend = ""; status = ""
        expand?()
    }
    func share() {
        guard session.winningPlan != nil else { return }
        persistDemo()
        if let insert { insert(session, link) }
        else { status = "Open SideQuest inside Messages to insert the final plan." }
    }
    func persistDemo() {
        defaults.set(try? APIJSON.encoder.encode(session), forKey: "demo-" + session.id)
    }
    func open(_ url: URL) {
        guard let incoming = try? SessionLink.decode(url), incoming.isDemo,
              let data = defaults.data(forKey: "demo-" + incoming.sessionId),
              let saved = try? APIJSON.decoder.decode(SideQuestSession.self, from: data),
              let context = saved.context, PlanRules.validate(saved.planOptions, for: context) else { return }
        task?.cancel(); session = saved
        stage = saved.winningPlan == nil ? .plans : .winner
        status = ""
    }
    func rememberMapsReturn(now: Date = Date()) {
        guard insert != nil, let url = try? link.url() else { return }
        persistDemo()
        defaults.set(["url": url.absoluteString, "created": now.timeIntervalSince1970],
                     forKey: "demo-maps-return")
    }
    @discardableResult func resumeAfterMaps(now: Date = Date()) -> Bool {
        guard let marker = defaults.dictionary(forKey: "demo-maps-return") else { return false }
        defaults.removeObject(forKey: "demo-maps-return")
        guard let created = marker["created"] as? Double, (0...600).contains(now.timeIntervalSince1970 - created),
              let value = marker["url"] as? String, let url = URL(string: value) else { return false }
        open(url)
        return stage == .winner || stage == .plans
    }
}
