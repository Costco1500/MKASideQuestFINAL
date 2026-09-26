import XCTest
@testable import SideQuestCore

final class AvailabilityTests: XCTestCase {
    let day = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
    var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }
    func interval(_ start: Double, _ end: Double) -> CalendarBusyInterval {
        .init(start: day.addingTimeInterval(start * 3600), end: day.addingTimeInterval(end * 3600))
    }
    func person(_ busy: [CalendarBusyInterval], _ from: Double = 10, _ to: Double = 23) -> Participant {
        Participant(displayName: "A", approximateArea: "Midtown", availability: interval(from, to), busyIntervals: busy)
    }
    func testMergesUnsortedOverlappingAndTouchingIntervals() {
        XCTAssertEqual(AvailabilityEngine.normalize([interval(14, 16), interval(12, 15), interval(16, 17), interval(20, 19)]), [interval(12, 17)])
    }
    func testSharedWindowUsesEveryPersonsCalendarAndManualWindow() {
        let participants = [person([interval(10, 18)], 10, 22), person([interval(20, 23)], 17, 23)]
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows(participants, range: interval(0, 24), calendar: utc), [interval(18, 20)])
    }
    func testMinimumDurationAndReasonableHours() {
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([person([], 0, 24)], range: interval(0, 24), calendar: utc), [interval(10, 23)])
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([person([], 18, 19)], range: interval(0, 24), calendar: utc), [])
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([person([], 18, 19.5)], range: interval(0, 24), calendar: utc), [interval(18, 19.5)])
    }
    func testEmptyOrFullyBusyGroupsHaveNoCandidates() {
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([], range: interval(0, 24), calendar: utc), [])
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([person([interval(0, 24)])], range: interval(0, 24), calendar: utc), [])
        XCTAssertEqual(AvailabilityEngine.sharedFreeWindows([person([])], range: interval(24, 0), calendar: utc), [])
    }
    func testFreeWindowsClipBusyIntervalsToRange() {
        XCTAssertEqual(AvailabilityEngine.freeWindows(busy: [interval(0, 11), interval(20, 24)], range: interval(10, 23)), [interval(11, 20)])
    }
    func testBestTimesFavorWeekendAndFridayEveningsOverWeeknights() {
        // 2026-10-01 is a Thursday; the range covers Thursday through Saturday.
        let slots = AvailabilityEngine.bestTimes([person([], 0, 72)], range: interval(0, 72), calendar: utc)
        XCTAssertEqual(slots.map(\.window), [interval(42, 46), interval(66, 70), interval(18, 22)])
        XCTAssertEqual(slots[0].reasons, ["Friday night", "Wide open"])
        XCTAssertTrue(slots[0].score >= slots[1].score && slots[1].score > slots[2].score)
    }
    func testBestTimesAvoidEveryonesBusyTimeAndPreferDifferentDays() {
        let busyFridayEvening = [person([interval(41, 47)], 0, 72), person([interval(8, 17)], 0, 72)]
        let slots = AvailabilityEngine.bestTimes(busyFridayEvening, range: interval(0, 72), calendar: utc)
        XCTAssertEqual(slots.map(\.window), [interval(66, 70), interval(18, 22), interval(36, 40)])
        let oneDay = AvailabilityEngine.bestTimes([person([interval(14, 17)])], range: interval(0, 24), calendar: utc)
        XCTAssertEqual(oneDay.map(\.window), [interval(18, 22), interval(10, 14)])
    }
    func testBestTimesGiveNoticeAndNeverStartInThePast() {
        let slots = AvailabilityEngine.bestTimes([person([])], range: interval(0, 24), now: day.addingTimeInterval(16.75 * 3600), calendar: utc)
        XCTAssertEqual(slots.map(\.window), [interval(19, 23)])
        XCTAssertFalse(slots[0].reasons.contains("Starts soon"))
        let late = AvailabilityEngine.bestTimes([person([])], range: interval(0, 24), now: day.addingTimeInterval(21.75 * 3600), calendar: utc)
        XCTAssertEqual(late, [])
    }
    func testPlanningRequestUsesTheBestTimesAsCandidates() {
        let people = [person([interval(10, 18)], 10, 22), person([interval(20, 23)], 17, 23)]
        let request = PlanningRequest(participants: people, messages: [], now: day, calendar: utc)
        XCTAssertEqual(request.candidateTimeWindows, [interval(18, 20)])
    }
    func testCalendarPermissionUsageDescriptionIsPresent() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"))
    }
}
