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
    func testCalendarPermissionUsageDescriptionIsPresent() {
        XCTAssertNotNil(Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription"))
    }
}
