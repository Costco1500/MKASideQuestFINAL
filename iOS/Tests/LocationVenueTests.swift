import XCTest
import MapKit
@testable import SideQuestCore

final class LocationVenueTests: XCTestCase {
    func testGroupCenterUsesOnlyAvailableValidLocations() {
        let a = ParticipantLocation(latitude: 33.7, longitude: -84.3, displayArea: "Atlanta")
        let b = ParticipantLocation(latitude: 33.9, longitude: -84.5, displayArea: nil)
        XCTAssertEqual(ParticipantLocation.center(of: [a]), a)
        let center = ParticipantLocation.center(of: [a, b])
        XCTAssertEqual(center!.latitude, 33.8, accuracy: 0.0001)
        XCTAssertEqual(center!.longitude, -84.4, accuracy: 0.0001)
        XCTAssertNil(ParticipantLocation.center(of: []))
        XCTAssertNil(ParticipantLocation.center(of: [.init(latitude: 999, longitude: 0, displayArea: nil)]))
    }
    func testExactParticipantCoordinatesNeverEnterServerOrLLMContext() throws {
        var person = DemoData.participants()[0]
        person.location = ParticipantLocation(latitude: 33.778123, longitude: -84.398456, displayArea: "Midtown Atlanta")
        let data = try APIJSON.encoder.encode(ParticipantBody(person))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let profile = try XCTUnwrap(object["participant"] as? [String: Any])
        let location = try XCTUnwrap(profile["location"] as? [String: Any])
        XCTAssertEqual(location["latitude"] as? Double, 33.78)
        XCTAssertEqual(location["longitude"] as? Double, -84.40)
        let request = PlanningRequest(participants: [person], messages: [])
        let wire = String(decoding: try APIJSON.encoder.encode(request), as: UTF8.self)
        XCTAssertFalse(wire.contains("latitude"))
        XCTAssertFalse(wire.contains("longitude"))
        XCTAssertFalse(wire.contains("33.778123"))
    }
    func testVenueRoundTripsAndOldPlansStillDecodeWithoutVenue() throws {
        let venue = PlanVenue(name: "A MapKit result", address: "123 Example St", latitude: 33.78, longitude: -84.39)
        XCTAssertEqual(try APIJSON.decoder.decode(PlanVenue.self, from: APIJSON.encoder.encode(venue)), venue)
        let request = PlanningRequest(participants: DemoData.participants(), messages: [])
        let plans = try DemoPlanner.plans(for: request)
        XCTAssertTrue(PlanRules.validate(plans, for: request))
        let old = try APIJSON.decoder.decode([PlanOption].self, from: APIJSON.encoder.encode(plans))
        XCTAssertNil(old[0].venue)
        XCTAssertNotNil(old[0].venueSearchQuery)
    }
    func testVenueSelectionSkipsParkingForParkPlans() {
        let parking = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 33.78, longitude: -84.39)))
        parking.name = "Public Parking"; parking.pointOfInterestCategory = .parking
        let park = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 33.79, longitude: -84.38)))
        park.name = "A real park"; park.pointOfInterestCategory = .park
        XCTAssertEqual(VenueResolver.venue(from: [parking, park], query: "public park")?.name, "A real park")
        XCTAssertNil(VenueResolver.venue(from: [parking], query: "public park"))
    }
    func testVenueSelectionRejectsDistantResultsOutsideGroupArea() {
        let distant = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 43.9919, longitude: -76.0217)))
        distant.name = "Distant airport"
        let nearby = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: 33.79, longitude: -84.38)))
        nearby.name = "Nearby cafe"
        XCTAssertEqual(VenueResolver.venue(from: [distant, nearby], query: "cafe", center: DemoData.location)?.name, "Nearby cafe")
        XCTAssertNil(VenueResolver.venue(from: [distant], query: "cafe", center: DemoData.location))
    }
    func testResolutionFailureDoesNotFabricateCoordinates() async throws {
        let request = PlanningRequest(participants: DemoData.participants(), messages: [])
        let plans = try DemoPlanner.plans(for: request)
        let resolver = VenueResolver(search: { _, _, _ in nil })
        let result = await resolver.resolve(plans, participants: DemoData.participants())
        XCTAssertEqual(result.count, 3)
        XCTAssertTrue(result.allSatisfy { $0.venue == nil })
        XCTAssertTrue(PlanRules.validate(result, for: request))
    }
    func testResolverUsesMapResultAndCalendarGetsVenueAddress() async throws {
        let request = PlanningRequest(participants: DemoData.participants(), messages: [])
        let plans = try DemoPlanner.plans(for: request)
        let found = PlanVenue(name: "Verified place", address: "123 Example St", latitude: 33.78, longitude: -84.39)
        let resolver = VenueResolver(search: { query, center, area in
            XCTAssertFalse(query.isEmpty); XCTAssertFalse(area.isEmpty)
            return found
        })
        let result = await resolver.resolve(plans, participants: DemoData.participants())
        XCTAssertEqual(result.first?.venue, found)
        XCTAssertEqual(result.first?.calendarLocation, "Verified place, 123 Example St")
    }
}
