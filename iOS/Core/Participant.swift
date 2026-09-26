import Foundation

public enum AgeRange: String, Codable, CaseIterable, Sendable {
    case under18 = "under18", eighteenToTwenty = "18–20", twentyOnePlus = "21+"
    public var label: String { self == .under18 ? "Under 18" : rawValue }
    public var minimumEligibleAge: Int {
        switch self { case .under18: return 0; case .eighteenToTwenty: return 18; case .twentyOnePlus: return 21 }
    }
}

public struct CalendarBusyInterval: Codable, Equatable, Sendable {
    public var start: Date
    public var end: Date
    public init(start: Date, end: Date) { self.start = start; self.end = end }
    public var duration: TimeInterval { end.timeIntervalSince(start) }
}

public struct ParticipantLocation: Codable, Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var displayArea: String?
    public init(latitude: Double, longitude: Double, displayArea: String?) {
        self.latitude = latitude; self.longitude = longitude; self.displayArea = displayArea
    }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
    public var coarse: ParticipantLocation {
        .init(latitude: (latitude * 100).rounded() / 100, longitude: (longitude * 100).rounded() / 100, displayArea: displayArea)
    }
    public static func center(of locations: [ParticipantLocation]) -> ParticipantLocation? {
        let valid = locations.filter(\.isValid)
        guard !valid.isEmpty else { return nil }
        if valid.count == 1 { return valid[0] }
        let latitude = valid.reduce(0.0) { $0 + $1.latitude } / Double(valid.count)
        let longitude = valid.reduce(0.0) { $0 + $1.longitude } / Double(valid.count)
        return ParticipantLocation(latitude: latitude, longitude: longitude, displayArea: nil)
    }
}

public struct Participant: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var ageRange: AgeRange
    public var maxBudget: Double
    public var approximateArea: String
    public var availability: CalendarBusyInterval
    public var busyIntervals: [CalendarBusyInterval]
    public var calendarConnectionStatus: String
    public var location: ParticipantLocation?

    public init(id: String = UUID().uuidString, displayName: String = "", ageRange: AgeRange = .eighteenToTwenty,
                maxBudget: Double = 25, approximateArea: String = "", availability: CalendarBusyInterval,
                busyIntervals: [CalendarBusyInterval] = [], calendarConnectionStatus: String = "manual", location: ParticipantLocation? = nil) {
        self.id = id; self.displayName = displayName; self.ageRange = ageRange; self.maxBudget = maxBudget
        self.approximateArea = approximateArea; self.availability = availability
        self.busyIntervals = busyIntervals; self.calendarConnectionStatus = calendarConnectionStatus; self.location = location
    }

    public var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayName.count <= 60 &&
        !approximateArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && approximateArea.count <= 120 &&
        (location?.isValid ?? true) && maxBudget.isFinite && (0...500).contains(maxBudget) && availability.duration >= 90 * 60 && availability.duration <= 7 * 86400
    }

    public static func groupBudget(_ participants: [Participant]) -> Double? { participants.map(\.maxBudget).min() }
}

public enum DemoData {
    public static let location = ParticipantLocation(latitude: 33.7834, longitude: -84.3831, displayArea: "Midtown Atlanta")
    public static func range(now: Date = Date(), calendar: Calendar = .current) -> CalendarBusyInterval {
        let day = calendar.nextDate(after: now, matching: DateComponents(hour: 17, weekday: 5), matchingPolicy: .nextTime)!
        return CalendarBusyInterval(start: day, end: calendar.date(byAdding: .hour, value: 5, to: day)!)
    }

    public static func participants(now: Date = Date()) -> [Participant] {
        let window = range(now: now)
        return zip(["Alex", "Maya", "Jake", "Sarah"], [25.0, 25, 20, 15]).enumerated().map { index, value in
            Participant(id: value.0.lowercased(), displayName: value.0,
                        ageRange: index == 2 ? .twentyOnePlus : .eighteenToTwenty,
                        maxBudget: value.1, approximateArea: "Georgia Tech / Midtown",
                        availability: window,
                        busyIntervals: index == 3 ? [] : [.init(start: window.start, end: window.start.addingTimeInterval(index == 0 ? 5400 : 3600))],
                        calendarConnectionStatus: "demo", location: [
                            ParticipantLocation(latitude: 33.7756, longitude: -84.3963, displayArea: "Georgia Tech"),
                            location,
                            ParticipantLocation(latitude: 33.8384, longitude: -84.3790, displayArea: "Buckhead"),
                            ParticipantLocation(latitude: 33.7785, longitude: -84.3987, displayArea: "Georgia Tech")
                        ][index])
        }
    }
}
