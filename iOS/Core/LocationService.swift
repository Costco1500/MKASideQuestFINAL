import Foundation
import Combine
import CoreLocation

@MainActor public final class LocationService: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published public private(set) var location: ParticipantLocation?
    @Published public private(set) var fetching = false
    @Published public private(set) var status = ""
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    public override init() {
        super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }
    public func requestLocation() {
        guard !fetching else { return }
        fetching = true; status = "Finding your nearby area…"
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: denied()
        }
    }
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard fetching else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        case .denied, .restricted: denied()
        default: break
        }
    }
    private func denied() {
        fetching = false; status = "Location is unavailable. Enter your area manually to keep going."
    }
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fetching = false; status = "We couldn't get your location. Try again or enter your area manually."
    }
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let found = locations.last, CLLocationCoordinate2DIsValid(found.coordinate), found.horizontalAccuracy >= 0 else { denied(); return }
        Task { @MainActor in
            let placemark = try? await geocoder.reverseGeocodeLocation(found).first
            let parts = [placemark?.subLocality, placemark?.locality].compactMap { $0 }
            let area = parts.isEmpty ? "Your nearby area" : Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: ", ")
            location = ParticipantLocation(latitude: found.coordinate.latitude, longitude: found.coordinate.longitude, displayArea: area)
            status = "Near \(area)"; fetching = false
        }
    }
    #if DEBUG && targetEnvironment(simulator)
    public func useDemoLocation() {
        location = DemoData.location; fetching = false; status = "Demo · Near Midtown Atlanta"
    }
    #endif
}
