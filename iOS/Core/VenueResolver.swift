import Foundation
import MapKit

public struct PlanVenue: Codable, Equatable, Sendable {
    public var name: String
    public var address: String?
    public var latitude: Double
    public var longitude: Double
    /// Listed hours in OpenStreetMap syntax, when a matching place publishes them.
    public var openingHours: String? = nil
    public init(name: String, address: String?, latitude: Double, longitude: Double, openingHours: String? = nil) {
        self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude; self.openingHours = openingHours
    }
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    public var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
        item.name = name
        return item
    }
}

public struct VenueResolver {
    public typealias Search = (String, ParticipantLocation?, String) async -> PlanVenue?
    /// Nearby matches in relevance order, so a closed first result can give way to an open one.
    public typealias CandidateSearch = (String, ParticipantLocation?, String) async -> [PlanVenue]
    private let search: CandidateSearch
    private let hours: OpeningHoursDirectory.Lookup?
    public init() { search = Self.searchMapKit; hours = OpeningHoursDirectory.live }
    public init(search: @escaping Search) {
        self.search = { query, center, area in await search(query, center, area).map { [$0] } ?? [] }
        hours = nil
    }
    public init(candidates: @escaping CandidateSearch, hours: OpeningHoursDirectory.Lookup?) {
        search = candidates; self.hours = hours
    }
    public func resolve(_ plans: [PlanOption], participants: [Participant]) async -> [PlanOption] {
        let center = ParticipantLocation.center(of: participants.compactMap(\.location))
        var options: [[PlanVenue]] = []
        for plan in plans {
            if Task.isCancelled { return plans.map { var p = $0; p.venue = nil; return p } }
            let query = String((plan.venueSearchQuery ?? plan.activity).prefix(200))
            options.append(Array(await search(query, center, plan.area).filter(\.isValid).prefix(4)))
        }
        // One hours request covers every candidate for every plan.
        let flat = options.flatMap { $0 }
        if let hours, !flat.isEmpty {
            let listed = await hours(flat)
            var index = 0
            for plan in options.indices {
                for candidate in options[plan].indices {
                    if index < listed.count { options[plan][candidate].openingHours = listed[index] }
                    index += 1
                }
            }
        }
        if Task.isCancelled { return plans.map { var p = $0; p.venue = nil; return p } }
        return zip(plans, options).map { plan, candidates in
            var grounded = plan
            grounded.venue = Self.choose(candidates, from: plan.start, to: plan.end)
            return grounded
        }
    }
    /// Prefers a place listed as open for the whole plan, then unknown hours, keeping MapKit's order on ties.
    static func choose(_ candidates: [PlanVenue], from start: Date, to end: Date) -> PlanVenue? {
        candidates.enumerated().min { left, right in
            let a = left.element.hoursStatus(from: start, to: end).preference
            let b = right.element.hoursStatus(from: start, to: end).preference
            return a == b ? left.offset < right.offset : a < b
        }?.element
    }
    /// Finds real places for a free-text query near the group, for plans and the "Is it open?" check.
    public static func searchMapKit(query: String, center: ParticipantLocation?, area: String) async -> [PlanVenue] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = center == nil ? query + " near " + area : query
        request.resultTypes = .pointOfInterest
        if let center {
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                               latitudinalMeters: 24_000, longitudinalMeters: 24_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        return venues(from: response.mapItems, query: query, center: center)
    }
    static func venue(from items: [MKMapItem], query: String, center: ParticipantLocation? = nil) -> PlanVenue? {
        venues(from: items, query: query, center: center).first
    }
    static func venues(from items: [MKMapItem], query: String, center: ParticipantLocation? = nil) -> [PlanVenue] {
        let seeksParking = query.localizedCaseInsensitiveContains("parking")
        return items.filter { item in
            let parking = item.pointOfInterestCategory == .parking || (item.name?.localizedCaseInsensitiveContains("parking") == true)
            let withinArea = center.map { center in
                CLLocation(latitude: center.latitude, longitude: center.longitude)
                    .distance(from: CLLocation(latitude: item.placemark.coordinate.latitude, longitude: item.placemark.coordinate.longitude)) <= 25_000
            } ?? true
            return item.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false &&
                CLLocationCoordinate2DIsValid(item.placemark.coordinate) && (!parking || seeksParking) && withinArea
        }.map { item in
            let place = item.placemark
            let street = [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ")
            let address = [street, place.locality, place.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            return PlanVenue(name: item.name!, address: address.isEmpty ? nil : address,
                             latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
        }
    }
}
