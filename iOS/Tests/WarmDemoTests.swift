import XCTest
import UIKit
import CoreLocation
@testable import SideQuest
@testable import SideQuestCore

final class WarmDemoTests: XCTestCase {
    func testConversationFeelsLikeAGroupAndUsesExistingSelection() {
        var messages = DemoConversation.messages
        XCTAssertTrue((30...40).contains(messages.count))
        XCTAssertEqual(Set(messages.map(\.sender)), Set(["Alex", "Maya", "Jake", "Sarah"]))
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("pottery") })
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("boba") })
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("laundry") })
        messages += MessageImport.parse((0..<30).map { "Alex: extra \($0)" }.joined(separator: "\n"))
        MessageImport.select(.latest50, in: &messages)
        XCTAssertEqual(messages.filter(\.isSelected).count, 50)
        XCTAssertEqual(MessageImport.analysisMessages(messages).count, 50)
    }
    func testWarmColorsAreReadableInLightAndDarkMode() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let background = QuestPalette.background.resolvedColor(with: traits)
            let text = QuestPalette.text.resolvedColor(with: traits)
            let fill = QuestPalette.primaryFill.resolvedColor(with: traits)
            let buttonText = QuestPalette.primaryText.resolvedColor(with: traits)
            XCTAssertGreaterThan(contrast(background, text), 7)
            XCTAssertGreaterThanOrEqual(contrast(fill, buttonText), 4.5)
            XCTAssertNotEqual(background, .black)
            XCTAssertNotEqual(background, .white)
        }
    }
    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            let linear = [r,g,b].map { v -> Double in let d = Double(v); return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x,y) + 0.05) / (min(x,y) + 0.05)
    }
}

@MainActor final class OfflineDemoTests: XCTestCase {
    private func makeStore() -> QuestStore { QuestStore(phaseDelay: .zero, voteDelay: .zero) }
    private func settle(_ store: QuestStore) async throws {
        for _ in 0..<100 where store.busy { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(store.busy)
    }
    func testLaunchAndResetNeedNoSetup() async throws {
        let store = makeStore()
        XCTAssertEqual(store.stage, .conversation)
        XCTAssertEqual(store.messages.count, 38)
        XCTAssertTrue(store.session.planOptions.isEmpty)
        store.analyze(); try await settle(store)
        XCTAssertEqual(store.stage, .understanding)
        store.showPlans()
        store.vote(store.session.planOptions[0], value: .down)
        store.simulateGroupVotes(); try await settle(store)
        store.reset()
        XCTAssertEqual(store.stage, .conversation)
        XCTAssertEqual(store.messages.count, 38)
        XCTAssertTrue(store.session.planOptions.isEmpty)
        XCTAssertTrue(store.session.votes.isEmpty)
        XCTAssertNil(store.session.winningPlan)
    }
    func testExactlyThreeOfflinePlansExplainEveryFriendAndMeetConstraints() async throws {
        let store = makeStore(); store.analyze(); store.analyze(); try await settle(store)
        XCTAssertEqual(store.session.source, "demo")
        XCTAssertEqual(store.session.planOptions.map(\.title), ["Clay & Boba", "Sunset Picnic + Cards", "Gallery + Dessert"])
        XCTAssertTrue(PlanRules.validate(store.session.planOptions, for: try XCTUnwrap(store.session.context)))
        XCTAssertEqual(store.session.planOptions.map(\.estimatedCostPerPerson), [12, 8, 10])
        XCTAssertTrue(store.session.planOptions.allSatisfy { Calendar.current.component(.hour, from: $0.start) == 19 })
        XCTAssertTrue(store.session.planOptions[0].whyItWorks["maya"]!.contains("pottery"))
    }
    func testEachPlanNamesARealNearbyBusinessWithItsStreetAddress() async throws {
        let store = makeStore(); store.analyze(); try await settle(store)
        let plans = store.session.planOptions
        let venues = plans.compactMap(\.venue)
        XCTAssertEqual(venues.map(\.name), ["Glaze Tea", "Piedmont Park", "Atlanta Contemporary"])
        XCTAssertEqual(venues.map(\.address), ["960 Spring St NW, Atlanta, GA 30309", "1320 Monroe Dr NE, Atlanta, GA 30306", "535 Means St NW, Atlanta, GA 30318"])
        XCTAssertTrue(venues.allSatisfy { $0.isValid && $0.placeID?.isEmpty == false })
        // Walkable or a short ride from Tech Square, where the chat says the group is.
        let techSquare = CLLocation(latitude: 33.7768, longitude: -84.3890)
        XCTAssertTrue(venues.allSatisfy { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: techSquare) < 3_000 })
        XCTAssertEqual(plans[2].secondStop, "Insomnia Cookies · 930 Spring St NW")
        XCTAssertEqual(plans[0].calendarLocation, "Glaze Tea, 960 Spring St NW, Atlanta, GA 30309")
        XCTAssertFalse(plans.flatMap(\.concerns).joined().localizedCaseInsensitiveContains("meetup point"))
    }
    func testGroupVotesAreDeterministicAndUseVoteEngine() async throws {
        let store = makeStore(); store.analyze(); try await settle(store); store.showPlans()
        store.vote(store.session.planOptions[0], value: .down)
        store.simulateGroupVotes(); store.simulateGroupVotes(); try await settle(store)
        XCTAssertEqual(store.stage, .winner)
        XCTAssertEqual(store.session.votes.count, 12)
        XCTAssertEqual(store.session.winningPlan?.id, "plan-1")
        XCTAssertEqual(store.session.winningPlan?.id, VoteEngine.winner(in: store.session)?.id)
        store.reset(); store.analyze(); try await settle(store); store.showPlans()
        store.vote(store.session.planOptions[0], value: .pass)
        store.vote(store.session.planOptions[1], value: .down)
        store.simulateGroupVotes(); try await settle(store)
        XCTAssertEqual(store.session.winningPlan?.id, "plan-2", "Alex's vote must count; never hardcode the winner")
    }
    func testResetCancelsInFlightAnalysis() async throws {
        let store = QuestStore(phaseDelay: .milliseconds(25), voteDelay: .zero)
        store.analyze(); store.reset()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(store.stage, .conversation)
        XCTAssertTrue(store.session.planOptions.isEmpty)
    }
    func testWinningDemoResumesAfterMapsAndInsertsOnlyOnRequest() async throws {
        let store = makeStore(); store.analyze(); try await settle(store); store.showPlans()
        store.vote(store.session.planOptions[0], value: .down)
        store.simulateGroupVotes(); try await settle(store)
        var inserted: SessionLink?
        store.insert = { _, link in inserted = link }
        XCTAssertNil(inserted)
        store.rememberMapsReturn()
        let reopened = makeStore()
        XCTAssertTrue(reopened.resumeAfterMaps())
        XCTAssertEqual(reopened.stage, .winner)
        XCTAssertEqual(reopened.session.winningPlan?.id, "plan-1")
        store.share(); XCTAssertTrue(try XCTUnwrap(inserted).isDemo)
        XCTAssertFalse(makeStore().resumeAfterMaps())
    }
}
