import XCTest
@testable import SideQuestCore

final class SessionTests: XCTestCase {
    func session() throws -> SideQuestSession { try SideQuestSession.demo() }
    func testWinnerCountsLatestVotePerMemberAndRejectsUnknownVotes() throws {
        var session = try session()
        session.votes = [Vote(participantId: "alex", planId: "plan-1", value: .down),
                         Vote(participantId: "alex", planId: "plan-1", value: .pass),
                         Vote(participantId: "maya", planId: "plan-2", value: .maybe),
                         Vote(participantId: "stranger", planId: "plan-1", value: .down)]
        XCTAssertEqual(VoteEngine.winner(in: session)?.id, "plan-2")
    }
    func testTieBreakUsesDownThenPassThenFitThenStableOrder() throws {
        var session = try session()
        session.votes = [.init(participantId: "alex", planId: "plan-1", value: .maybe),
                         .init(participantId: "maya", planId: "plan-1", value: .maybe),
                         .init(participantId: "alex", planId: "plan-2", value: .down)]
        XCTAssertEqual(VoteEngine.winner(in: session)?.id, "plan-2")
        session.votes = [.init(participantId: "alex", planId: "plan-1", value: .down),
                         .init(participantId: "alex", planId: "plan-2", value: .down),
                         .init(participantId: "maya", planId: "plan-1", value: .pass)]
        XCTAssertEqual(VoteEngine.winner(in: session)?.id, "plan-2")
        session.votes.removeLast()
        XCTAssertEqual(VoteEngine.winner(in: session)?.id, "plan-1")
        session.planOptions[1].groupFitScore = session.planOptions[0].groupFitScore
        XCTAssertEqual(VoteEngine.winner(in: session)?.id, "plan-1")
    }
    func testHardConstraintsCannotWinAndNoVotesMeansNoWinner() throws {
        var session = try session()
        XCTAssertNil(VoteEngine.winner(in: session))
        session.votes = [.init(participantId: "alex", planId: "plan-1", value: .down)]
        session.planOptions[0].estimatedCostPerPerson = 999
        XCTAssertNil(VoteEngine.winner(in: session))
    }
    func testLinkRoundTripsOnlyLightweightMetadataAndRejectsForeignLinks() throws {
        let link = SessionLink(sessionId: UUID().uuidString, inviteToken: String(repeating: "a", count: 43), serverURL: URL(string: "https://api.example.com")!, isDemo: false)
        let url = try link.url()
        XCTAssertEqual(try SessionLink.decode(url), link)
        XCTAssertLessThan(url.absoluteString.count, 500)
        XCTAssertThrowsError(try SessionLink.decode(URL(string: "https://evil.example/session/123")!))
        XCTAssertThrowsError(try SessionLink.decode(URL(string: url.absoluteString + "&invite=duplicate")!))
        XCTAssertThrowsError(try APIClient(baseURL: URL(string: "http://example.com")!))
    }
}
