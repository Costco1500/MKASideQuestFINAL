import XCTest
@testable import SideQuestCore

final class OpeningHoursTests: XCTestCase {
    /// 2026-10-01 is a Thursday.
    let thursday = ISO8601DateFormatter().date(from: "2026-10-01T00:00:00Z")!
    var utc: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!; return calendar }
    func at(_ hours: Double, dayOffset: Int = 0) -> Date { thursday.addingTimeInterval(Double(dayOffset) * 86400 + hours * 3600) }
    func status(_ hours: String, _ start: Double, _ end: Double, dayOffset: Int = 0) -> VenueHoursStatus {
        guard let parsed = OpeningHours(osm: hours) else { return .unknown }
        return parsed.status(from: at(start, dayOffset: dayOffset), to: at(end, dayOffset: dayOffset), calendar: utc)
    }

    func testLateNightHoursSpillPastMidnight() {
        let hours = "Mo-Th,Su 11:00-24:00; Fr-Sa 11:00-02:00"
        XCTAssertEqual(status(hours, 19, 21), .open(until: at(24), allDay: false))
        XCTAssertEqual(status(hours, 23, 25, dayOffset: 1), .open(until: at(26, dayOffset: 1), allDay: false))
        XCTAssertEqual(status(hours, 23, 25), .closesEarly(at: at(24)))
    }
    func testClosedEarlyAndLateOpeningAreDistinguished() {
        let cafe = "Tu-Fr 08:00-16:00; Sa,Su 09:00-17:00"
        XCTAssertEqual(status(cafe, 18.5, 20.5), .closed)
        XCTAssertEqual(status(cafe, 15, 17), .closesEarly(at: at(16)))
        XCTAssertEqual(status(cafe, 7, 9), .opensLate(at: at(8)))
        XCTAssertEqual(status(cafe, 10, 12, dayOffset: 4), .closed, "Closed Mondays")
        XCTAssertEqual(status(cafe, 10, 12, dayOffset: 3), .open(until: at(17, dayOffset: 3), allDay: false))
    }
    func testAlwaysOpenAndEverydayHours() {
        XCTAssertEqual(status("24/7", 22, 26), .open(until: at(48), allDay: true))
        XCTAssertEqual(status("Mo-Su 00:00-24:00", 9, 11), .open(until: at(48), allDay: true))
        XCTAssertEqual(status("11:00-21:00", 12, 14, dayOffset: 2), .open(until: at(21, dayOffset: 2), allDay: false))
    }
    func testAdditionalRulesDayListsAndSplitTimes() {
        XCTAssertEqual(status("Su 11:00-24:00, Mo-Sa 11:00-02:00", 22, 24.5), .open(until: at(26), allDay: false))
        let mondayWednesday = "Mo, We 10:00-12:00"
        XCTAssertEqual(status(mondayWednesday, 10, 11, dayOffset: 4), .open(until: at(12, dayOffset: 4), allDay: false))
        XCTAssertEqual(status(mondayWednesday, 10, 11), .closed)
        let lunchBreak = "Mo-Fr 08:00-12:00, 13:00-17:30; PH off"
        XCTAssertEqual(status(lunchBreak, 12.5, 14), .opensLate(at: at(13)))
        XCTAssertEqual(status(lunchBreak, 13, 17), .open(until: at(17.5), allDay: false))
        XCTAssertEqual(status("Mo-Fr 11:30-22:00; Sa 17:00-22:00; Su off", 12, 14, dayOffset: 3), .closed)
        XCTAssertEqual(status("Fr-Mo 10:00-18:00", 12, 14, dayOffset: 3), .open(until: at(18, dayOffset: 3), allDay: false))
        XCTAssertEqual(status("Fr-Mo 10:00-18:00", 12, 14, dayOffset: 5), .closed, "Tuesday is outside Fr-Mo")
    }
    func testUnsupportedSyntaxIsUnknownInsteadOfGuessed() {
        for hours in ["", "by appointment", "\"by appointment\"", "sunrise-sunset", "Mo-Fr 09:00+", "Jan-Mar Mo-Fr 10:00-16:00", "Mo", "Mo-Fr 25:00-26:00", "off"] {
            XCTAssertNil(OpeningHours(osm: hours), hours)
        }
        let venue = PlanVenue(name: "Somewhere", address: nil, latitude: 33.78, longitude: -84.38, openingHours: "by appointment")
        XCTAssertEqual(venue.hoursStatus(from: at(18), to: at(20), calendar: utc), .unknown)
        XCTAssertEqual(PlanVenue(name: "No data", address: nil, latitude: 0, longitude: 0).hoursStatus(from: at(18), to: at(20)), .unknown)
    }
    func testDirectoryMatchesSameNamedPlaceNearTheVenue() throws {
        let json = """
        {"elements":[
          {"type":"node","lat":33.7801,"lon":-84.3899,"tags":{"name":"Binders Art Supplies and Frames","opening_hours":"Mo-Sa 10:00-19:00"}},
          {"type":"way","center":{"lat":33.7802,"lon":-84.3900},"tags":{"name":"Other Shop","opening_hours":"24/7"}},
          {"type":"node","lat":33.9000,"lon":-84.3900,"tags":{"name":"Binders Art Supplies & Frames","opening_hours":"Su 12:00-17:00"}}
        ]}
        """
        let result = try JSONDecoder().decode(OpeningHoursDirectory.OverpassResult.self, from: Data(json.utf8))
        let venue = PlanVenue(name: "Binders Art Supplies & Frames", address: nil, latitude: 33.7800, longitude: -84.3900)
        XCTAssertEqual(OpeningHoursDirectory.match(venue, in: result.elements), "Mo-Sa 10:00-19:00")
        let unmatched = PlanVenue(name: "A different gallery", address: nil, latitude: 33.7800, longitude: -84.3900)
        XCTAssertNil(OpeningHoursDirectory.match(unmatched, in: result.elements))
        XCTAssertTrue(OpeningHoursDirectory.sameName(OpeningHoursDirectory.normalized("The Clay Studio"), OpeningHoursDirectory.normalized("Clay Studio")))
    }
    func testResolverPrefersAnOpenPlaceAndOnlySendsVenueDetailsForHours() async throws {
        let people = DemoData.participants()
        let plans = try DemoPlanner.plans(for: PlanningRequest(participants: people, messages: []))
        let closed = PlanVenue(name: "Closes at four", address: nil, latitude: 33.78, longitude: -84.39)
        let open = PlanVenue(name: "Open late", address: nil, latitude: 33.781, longitude: -84.391)
        let unknown = PlanVenue(name: "No listing", address: nil, latitude: 33.782, longitude: -84.392)
        let resolver = VenueResolver(candidates: { query, _, _ in
            query == "public park" ? [closed, unknown] : [closed, open]
        }, hours: { venues in
            XCTAssertEqual(venues.count, 6)
            return venues.map { $0.name == "Closes at four" ? "Mo-Su 08:00-16:00" : ($0.name == "Open late" ? "Mo-Su 10:00-23:00" : nil) }
        })
        let result = await resolver.resolve(plans, participants: people)
        XCTAssertEqual(result[0].venue?.name, "Open late")
        XCTAssertEqual(result[0].venue?.openingHours, "Mo-Su 10:00-23:00")
        XCTAssertTrue(result[0].venue!.hoursStatus(from: result[0].start, to: result[0].end).isOpenForWholePlan)
        XCTAssertEqual(result[1].venue?.name, "No listing", "Unknown hours beat a place known to be closed")
    }
}
