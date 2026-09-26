import Foundation
import MapKit

public struct PlanVenue: Codable, Equatable, Sendable {
    public var name: String
    public var address: String?
    public var latitude: Double
    public var longitude: Double
    public init(name: String, address: String?, latitude: Double, longitude: Double) {
        self.name = name; self.address = address; self.latitude = latitude; self.longitude = longitude
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
    private let search: Search
    public init() { search = Self.searchMapKit }
    public init(search: @escaping Search) { self.search = search }
    public func resolve(_ plans: [PlanOption], participants: [Participant]) async -> [PlanOption] {
        let center = ParticipantLocation.center(of: participants.compactMap(\.location))
        var grounded: [PlanOption] = []
        for var plan in plans {
            if Task.isCancelled { return plans.map { var p = $0; p.venue = nil; return p } }
            let query = String((plan.venueSearchQuery ?? plan.activity).prefix(200))
            let found = await search(query, center, plan.area)
            plan.venue = found?.isValid == true ? found : nil
            grounded.append(plan)
        }
        return grounded
    }
    private static func searchMapKit(query: String, center: ParticipantLocation?, area: String) async -> PlanVenue? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query + " near " + area
        request.resultTypes = .pointOfInterest
        if let center {
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                                               latitudinalMeters: 24_000, longitudinalMeters: 24_000)
        }
        guard let response = try? await MKLocalSearch(request: request).start(),
              let item = response.mapItems.first(where: { $0.name != nil && CLLocationCoordinate2DIsValid($0.placemark.coordinate) }) else { return nil }
        let place = item.placemark
        let street = [place.subThoroughfare, place.thoroughfare].compactMap { $0 }.joined(separator: " ")
        let address = [street, place.locality, place.administrativeArea].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        return PlanVenue(name: item.name!, address: address.isEmpty ? nil : address,
                         latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
    }
}
