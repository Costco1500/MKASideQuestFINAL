import XCTest
import Security
@testable import SideQuest
@testable import SideQuestCore

@MainActor final class SessionWorkflowTests: XCTestCase {
    func waitUntilIdle(_ store: QuestStore) async throws {
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.busy)
    }

    func testEveryoneDoneIncludesPeopleWhoHaveNotJoinedYet() throws {
        var session = try SideQuestSession.demo()
        session.expectedParticipantCount = 5
        session.readyParticipantIds = session.participants.map(\.id)
        XCTAssertEqual(session.readyCount, 4)
        XCTAssertFalse(session.everyoneReady)
        session.expectedParticipantCount = 4
        session.readyParticipantIds = ["alex", "maya", "jake", "stranger"]
        XCTAssertEqual(session.readyCount, 3)
        XCTAssertFalse(session.everyoneReady)
        session.readyParticipantIds = session.participants.map(\.id)
        XCTAssertTrue(session.everyoneReady)
        session.participants[0].displayName = ""
        XCTAssertFalse(session.everyoneReady, "A Done flag cannot substitute for a valid profile")
    }

    func testOldCachedSessionWithoutReadinessFailsClosed() throws {
        let data = try APIJSON.encoder.encode(SideQuestSession.demo())
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "expectedParticipantCount")
        object.removeValue(forKey: "readyParticipantIds")
        let session = try APIJSON.decoder.decode(SideQuestSession.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertFalse(session.everyoneReady)
    }

    func testOrganizerCreatesInvitationBeforeEnteringAnyProfile() async throws {
        let previous = QuestPreferences.server
        QuestPreferences.server = "https://mock.sidequest.test"
        defer { QuestPreferences.server = previous; URLProtocol.unregisterClass(StubProtocol.self) }
        URLProtocol.registerClass(StubProtocol.self)
        var session = try SideQuestSession.demo()
        session.participants = []; session.planOptions = []; session.context = nil
        session.expectedParticipantCount = 4; session.readyParticipantIds = []
        let member = Membership(session: session, participantId: "host", memberToken: String(repeating: "m", count: 43), inviteToken: String(repeating: "i", count: 43), isOwner: true)
        var requests = 0
        StubProtocol.response = { request in
            requests += 1
            XCTAssertEqual(request.url?.path, "/api/sessions")
            return (200, try APIJSON.encoder.encode(member))
        }
        let store = QuestStore()
        var insertions = 0
        store.insert = { shared, _ in insertions += 1; XCTAssertTrue(shared.participants.isEmpty) }
        store.startSession(expectedParticipantCount: 4)
        try await waitUntilIdle(store)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(insertions, 1)
        XCTAssertEqual(store.session?.expectedParticipantCount, 4)
        XCTAssertFalse(store.canGenerate)
        if let link = store.link { SecItemDelete(MembershipVault.key(link) as CFDictionary) }
    }

    func testAnalyzeWaitsForEveryDoneAndPreventsDuplicatePlannerRequests() async throws {
        var session = try SideQuestSession.demo()
        session.planOptions = []; session.context = nil
        session.readyParticipantIds = Array(session.participants.map(\.id).dropLast())
        let store = QuestStore(); store.isDemo = true; store.session = session
        store.messages = DemoData.chatScript(nil)
        XCTAssertFalse(store.canGenerate)
        store.generate(); try await waitUntilIdle(store)
        XCTAssertTrue(store.session!.planOptions.isEmpty)
        XCTAssertEqual(store.messages.count, 8)
        session.readyParticipantIds = session.participants.map(\.id); store.session = session
        XCTAssertTrue(store.canGenerate)
        store.generate(); store.generate(); try await waitUntilIdle(store)
        XCTAssertEqual(store.session?.planOptions.count, 3)
        XCTAssertTrue(store.messages.isEmpty)
        XCTAssertFalse(store.canGenerate)
    }
}
