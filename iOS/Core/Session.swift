import Foundation

public enum VoteValue: String, Codable, CaseIterable, Sendable {
    case down, maybe, pass
    public var score: Int { self == .down ? 2 : (self == .maybe ? 1 : 0) }
    public var label: String { rawValue.capitalized }
}
public struct Vote: Codable, Equatable, Sendable {
    public var participantId: String
    public var planId: String
    public var value: VoteValue
    public init(participantId: String, planId: String, value: VoteValue) {
        self.participantId = participantId; self.planId = planId; self.value = value
    }
}
public struct SideQuestSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var participants: [Participant]
    public var context: PlanningRequest?
    public var planOptions: [PlanOption]
    public var votes: [Vote]
    public var winningPlanId: String?
    public var source: String
    public var revision: Int
    public var expectedParticipantCount: Int? = nil
    public var readyParticipantIds: [String]? = nil
    public var readyCount: Int {
        Set(readyParticipantIds ?? []).intersection(participants.filter(\.isValid).map(\.id)).count
    }
    public var everyoneReady: Bool {
        guard let expectedParticipantCount, (1...12).contains(expectedParticipantCount) else { return false }
        return participants.count == expectedParticipantCount && readyCount == expectedParticipantCount
    }
    public var winningPlan: PlanOption? {
        guard let context else { return nil }
        return planOptions.first { $0.id == winningPlanId && PlanRules.isEligible($0, for: context) }
    }

    public static func demo() throws -> SideQuestSession {
        let people = DemoData.participants()
        let request = PlanningRequest(participants: people, messages: [])
        return SideQuestSession(id: UUID().uuidString, participants: people, context: request,
                                planOptions: try DemoPlanner.plans(for: request), votes: [], source: "demo", revision: 0,
                                expectedParticipantCount: people.count, readyParticipantIds: people.map(\.id))
    }
}
public struct Membership: Codable, Sendable {
    public var session: SideQuestSession
    public var participantId: String
    public var memberToken: String
    public var inviteToken: String
    public var isOwner: Bool
}

public enum VoteEngine {
    public static func winner(in session: SideQuestSession) -> PlanOption? {
        guard let context = session.context else { return nil }
        let memberIDs = Set(session.participants.map(\.id))
        var latest: [String: Vote] = [:]
        for vote in session.votes where memberIDs.contains(vote.participantId) { latest[vote.participantId + ":" + vote.planId] = vote }
        let ranked = session.planOptions.enumerated().compactMap { index, plan -> (PlanOption, [Double])? in
            let votes = latest.values.filter { $0.planId == plan.id }
            guard !votes.isEmpty, PlanRules.isEligible(plan, for: context) else { return nil }
            return (plan, [Double(votes.reduce(0) { $0 + $1.value.score }), Double(votes.filter { $0.value == .down }.count),
                           -Double(votes.filter { $0.value == .pass }.count), plan.groupFitScore, -Double(index)])
        }
        return ranked.max { $0.1.lexicographicallyPrecedes($1.1) }?.0
    }
}

public struct SessionLink: Equatable, Sendable {
    public var sessionId: String
    public var inviteToken: String
    public var serverURL: URL
    public var isDemo: Bool
    public init(sessionId: String, inviteToken: String, serverURL: URL, isDemo: Bool) {
        self.sessionId = sessionId; self.inviteToken = inviteToken; self.serverURL = serverURL; self.isDemo = isDemo
    }
    public func url() throws -> URL {
        var parts = URLComponents(string: "https://sidequest.invalid/session/\(sessionId)")!
        parts.queryItems = [URLQueryItem(name: "invite", value: inviteToken), URLQueryItem(name: "server", value: serverURL.absoluteString), URLQueryItem(name: "demo", value: isDemo ? "1" : "0")]
        guard let url = parts.url else { throw PlanningError.invalidResponse }
        _ = try Self.decode(url)
        return url
    }
    public static func decode(_ url: URL) throws -> SessionLink {
        guard url.absoluteString.count < 2048, url.scheme == "https", url.host == "sidequest.invalid", url.user == nil, url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = parts.queryItems,
              items.count == 3, Set(items.map(\.name)) == Set(["invite", "server", "demo"]),
              url.pathComponents.count == 3, url.pathComponents[1] == "session", UUID(uuidString: url.lastPathComponent) != nil else { throw PlanningError.invalidResponse }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        guard let invite = values["invite"], (32...128).contains(invite.count), let server = URL(string: values["server"] ?? ""),
              ["0", "1"].contains(values["demo"] ?? "") else { throw PlanningError.invalidResponse }
        _ = try APIClient(baseURL: server)
        return SessionLink(sessionId: url.lastPathComponent, inviteToken: invite, serverURL: server, isDemo: values["demo"] == "1")
    }
}

public struct ParticipantBody: Encodable {
    public var participant: Participant
    public init(_ participant: Participant) {
        self.participant = participant; self.participant.location = participant.location?.coarse
    }
}
public struct VoteBody: Encodable {
    public var planId: String
    public var value: VoteValue
    public init(planId: String, value: VoteValue) { self.planId = planId; self.value = value }
}
public struct SessionPlanBody: Encodable {
    public var selectedMessages: [SelectedMessage]
    public var candidateTimeWindows: [CalendarBusyInterval]
    public var timeZone: String
    public init(_ request: PlanningRequest) {
        selectedMessages = request.selectedMessages; candidateTimeWindows = request.candidateTimeWindows; timeZone = request.timeZone
    }
}

public struct SessionVenueBody: Encodable {
    private var revision: Int
    private var venues: [VenueResult]
    public init(revision: Int, plans: [PlanOption]) {
        self.revision = revision; venues = plans.map { VenueResult(planId: $0.id, venue: $0.venue) }
    }
    private struct VenueResult: Encodable {
        var planId: String
        var venue: PlanVenue?
        enum CodingKeys: CodingKey { case planId, venue }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(planId, forKey: .planId); try values.encode(venue, forKey: .venue)
        }
    }
}
