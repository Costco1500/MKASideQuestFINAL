import XCTest
@testable import SideQuestCore

final class ProfileTests: XCTestCase {
    func testDemoContainsFourIndependentProfilesAndCoarseAreas() throws {
        let profiles = DemoData.participants()
        XCTAssertEqual(profiles.map(\.displayName), ["Alex", "Maya", "Jake", "Sarah"])
        XCTAssertEqual(Set(profiles.map(\.id)).count, 4)
        XCTAssertTrue(profiles.allSatisfy { !$0.approximateArea.isEmpty && $0.availability.start < $0.availability.end })
        XCTAssertEqual(try JSONDecoder().decode([Participant].self, from: JSONEncoder().encode(profiles)), profiles)
    }
    func testGroupBudgetUsesLowestComfortableMaximum() {
        XCTAssertEqual(Participant.groupBudget(DemoData.participants()), 15)
        XCTAssertNil(Participant.groupBudget([]))
    }
    func testInvalidSelfProfileCannotJoin() {
        var profile = DemoData.participants()[0]
        profile.displayName = "  "
        XCTAssertFalse(profile.isValid)
        profile.displayName = "Alex"
        profile.maxBudget = -1
        XCTAssertFalse(profile.isValid)
        profile.maxBudget = 0
        XCTAssertTrue(profile.isValid)
        profile.approximateArea = ""
        XCTAssertFalse(profile.isValid)
    }
    func testAgeOnlyDefinesActivityEligibility() {
        XCTAssertEqual(AgeRange.under18.minimumEligibleAge, 0)
        XCTAssertEqual(AgeRange.eighteenToTwenty.minimumEligibleAge, 18)
        XCTAssertEqual(AgeRange.twentyOnePlus.minimumEligibleAge, 21)
    }
}
