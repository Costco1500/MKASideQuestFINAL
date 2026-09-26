import XCTest
import Security
@testable import SideQuest
@testable import SideQuestCore

final class StubProtocol: URLProtocol {
    static var response: (URLRequest) throws -> (Int, Data) = { _ in (500, Data()) }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "mock.sidequest.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.response(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@MainActor final class ClientAndStoreTests: XCTestCase {
    var previousProfile: Data?
    override func setUp() {
        previousProfile = QuestPreferences.defaults.data(forKey: "profile")
        URLProtocol.registerClass(StubProtocol.self)
    }
    override func tearDown() {
        QuestPreferences.defaults.set(previousProfile, forKey: "profile")
        URLProtocol.unregisterClass(StubProtocol.self)
    }
    func idle(_ store: QuestStore) async throws {
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.busy)
    }
    func member(_ session: SideQuestSession, owner: Bool = true) -> Membership {
        Membership(session: session, participantId: session.participants[0].id, memberToken: String(repeating: "m", count: 43), inviteToken: String(repeating: "i", count: 43), isOwner: owner)
    }
    func testOfflineJourneyClearsChatVotesFinalizesAndReopens() async throws {
        QuestPreferences.demoChatScript = nil
        let store = QuestStore(); store.startDemo()
        XCTAssertTrue(store.messages.isEmpty)
        store.readChat(); XCTAssertTrue(store.isReading)
        for _ in 0..<100 where store.isReading { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(store.messages.count, 8)
        XCTAssertTrue(store.messages.allSatisfy(\.isSelected))
        XCTAssertEqual(store.status, "Found 8 messages in this chat.")
        store.generate(); try await idle(store)
        XCTAssertTrue(store.messages.isEmpty)
        let plan = try XCTUnwrap(store.session?.planOptions.first)
        store.vote(plan, value: .down); store.vote(plan, value: .maybe)
        XCTAssertEqual(store.session?.votes.count, 1)
        store.finalize(); XCTAssertEqual(store.session?.winningPlan?.id, plan.id)
        var inserted: URL?
        store.insert = { _, link in inserted = try? link.url() }
        store.share(); XCTAssertNotNil(inserted)
        let reopened = QuestStore(); reopened.open(try XCTUnwrap(inserted))
        XCTAssertEqual(reopened.session?.winningPlan?.id, plan.id)
        store.reset(); XCTAssertNil(store.session)
        store.open(URL(string: "https://invalid.example")!)
        XCTAssertFalse(store.status.isEmpty)
    }
    func testReadingChatStopsWhenExtensionCloses() async throws {
        QuestPreferences.demoChatScript = nil
        let store = QuestStore(); store.startDemo(); store.readChat()
        try await Task.sleep(for: .milliseconds(300))
        store.stopReading(); let partial = store.messages.count
        XCTAssertFalse(store.isReading)
        XCTAssertLessThan(partial, 8)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(store.messages.count, partial)
        XCTAssertTrue(store.status.isEmpty)
    }
    func testAPIClientEncodesAuthorizationAndDecodesPlans() async throws {
        let input = PlanningRequest(participants: DemoData.participants(), messages: [])
        let fixture = PlanResponse(plans: try DemoPlanner.plans(for: input), source: "ai")
        StubProtocol.response = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-member")
            return (200, try APIJSON.encoder.encode(fixture))
        }
        let client = try APIClient(baseURL: URL(string: "https://mock.sidequest.test")!)
        let result: PlanResponse = try await client.request("sidequest/plan", body: input, token: "test-member")
        XCTAssertEqual(result, fixture)
        StubProtocol.response = { _ in (403, Data("{}".utf8)) }
        do { let _: PlanResponse = try await client.plan(input); XCTFail("Must reject HTTP error") } catch { }
        StubProtocol.response = { _ in (200, Data("invalid json".utf8)) }
        do { let _: PlanResponse = try await client.plan(input); XCTFail("Must reject invalid JSON") } catch { }
    }
    func testSharedMemberRefreshVoteFinalizeAndOwnContext() async throws {
        let store = QuestStore()
        var session = try SideQuestSession.demo()
        let membership = member(session)
        let server = URL(string: "https://mock.sidequest.test")!
        try store.accept(membership, server: server)
        let link = try XCTUnwrap(store.link)
        defer { SecItemDelete(MembershipVault.key(link) as CFDictionary) }
        XCTAssertEqual(MembershipVault.load(link)?.participantId, membership.participantId)
        session.revision = 1
        StubProtocol.response = { _ in (200, try APIJSON.encoder.encode(session)) }
        await store.refresh(); XCTAssertEqual(store.session?.revision, 1)
        let plan = session.planOptions[0]
        session.votes = [Vote(participantId: membership.participantId, planId: plan.id, value: .down)]
        session.revision = 2
        store.vote(plan, value: .down); try await idle(store)
        XCTAssertEqual(store.session?.votes.count, 1)
        session.winningPlanId = plan.id; session.revision = 3
        store.finalize(); try await idle(store)
        XCTAssertEqual(store.session?.winningPlanId, plan.id)
        session.planOptions = []; session.votes = []; session.winningPlanId = nil; session.revision = 4
        store.saveProfile(session.participants[0]); try await idle(store)
        XCTAssertEqual(store.session?.planOptions.count, 0)
        let reopened = QuestStore(); reopened.open(try link.url())
        XCTAssertEqual(reopened.membership?.participantId, membership.participantId)
        StubProtocol.response = { _ in throw URLError(.notConnectedToInternet) }
        await store.refresh(); XCTAssertFalse(store.status.isEmpty)
    }
    func testCreatingAndJoiningShareOnlySelfProfile() async throws {
        let previous = QuestPreferences.server
        defer { QuestPreferences.server = previous }
        QuestPreferences.server = "https://mock.sidequest.test"
        let fixture = member(try SideQuestSession.demo())
        StubProtocol.response = { _ in (200, try APIJSON.encoder.encode(fixture)) }
        let store = QuestStore(); store.saveProfile(fixture.session.participants[0]); try await idle(store)
        XCTAssertEqual(store.membership?.participantId, fixture.participantId)
        let link = try XCTUnwrap(store.link)
        SecItemDelete(MembershipVault.key(link) as CFDictionary)
        let guest = QuestStore(); guest.open(try link.url())
        XCTAssertNil(guest.membership)
        guest.saveProfile(fixture.session.participants[0]); try await idle(guest)
        XCTAssertNotNil(guest.membership)
        SecItemDelete(MembershipVault.key(link) as CFDictionary)
    }
}
