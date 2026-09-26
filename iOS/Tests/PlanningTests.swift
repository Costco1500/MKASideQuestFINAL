import XCTest
@testable import SideQuestCore

final class PlanningTests: XCTestCase {
    func request() -> PlanningRequest {
        let participants = DemoData.participants()
        var messages = MessageImport.parse(DemoData.conversation)
        MessageImport.select(.all, in: &messages)
        return PlanningRequest(participants: participants, messages: messages)
    }
    func testDemoProducesExactlyThreeValidPlansAndJSONRoundTrips() throws {
        let input = request()
        let plans = try DemoPlanner.plans(for: input)
        XCTAssertEqual(plans.count, 3)
        XCTAssertTrue(PlanRules.validate(plans, for: input))
        let result = PlanResponse(plans: plans, source: "demo")
        XCTAssertEqual(try APIJSON.decoder.decode(PlanResponse.self, from: APIJSON.encoder.encode(result)), result)
    }
    func testRejectsBudgetAgeTimeDuplicateAndMissingFitViolations() throws {
        let input = request()
        let original = try DemoPlanner.plans(for: input)
        var plans = original; plans[0].estimatedCostPerPerson = 100
        XCTAssertFalse(PlanRules.validate(plans, for: input))
        plans = original; plans[0].minimumAge = 21
        XCTAssertFalse(PlanRules.validate(plans, for: input))
        plans = original; plans[0].end = plans[0].start.addingTimeInterval(30)
        XCTAssertFalse(PlanRules.validate(plans, for: input))
        plans = original; plans[0].start = .distantFuture
        XCTAssertFalse(PlanRules.validate(plans, for: input))
        plans = original; plans[0].id = plans[1].id
        XCTAssertFalse(PlanRules.validate(plans, for: input))
        plans = original; plans[0].whyItWorks = [:]
        XCTAssertFalse(PlanRules.validate(plans, for: input))
    }
    func testMinimizedRequestContainsNoCalendarMetadataOrDisplayNames() throws {
        let input = request()
        let json = String(data: try APIJSON.encoder.encode(input), encoding: .utf8)!
        XCTAssertFalse(json.contains("busyIntervals"))
        XCTAssertFalse(json.contains("calendarConnectionStatus"))
        XCTAssertFalse(json.contains("displayName"))
        XCTAssertTrue(json.contains("candidateTimeWindows"))
    }
    func testNoFreeWindowDoesNotInventPlans() {
        var people = DemoData.participants()
        people[0].busyIntervals = [people[0].availability]
        XCTAssertThrowsError(try DemoPlanner.plans(for: PlanningRequest(participants: people, messages: [])))
    }
    func testUnavailableBackendFallsBackToValidatedDemo() async throws {
        let result = try await PlanGenerator.generate(request(), remote: { _ in throw URLError(.notConnectedToInternet) })
        XCTAssertEqual(result.source, "demo")
        XCTAssertEqual(result.plans.count, 3)
    }
    func testValidRemoteResultRemainsAIAndInvalidRemoteFallsBack() async throws {
        let input = request()
        let expected = PlanResponse(plans: try DemoPlanner.plans(for: input), source: "ai")
        let good = try await PlanGenerator.generate(input, remote: { _ in expected })
        XCTAssertEqual(good.source, "ai")
        let bad = try await PlanGenerator.generate(input, remote: { _ in PlanResponse(plans: [], source: "ai") })
        XCTAssertEqual(bad.source, "demo")
    }
}
