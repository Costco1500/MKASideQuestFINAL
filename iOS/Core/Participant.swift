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

public struct Participant: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var ageRange: AgeRange
    public var maxBudget: Double
    public var approximateArea: String
    public var availability: CalendarBusyInterval
    public var busyIntervals: [CalendarBusyInterval]
    public var calendarConnectionStatus: String

    public init(id: String = UUID().uuidString, displayName: String = "", ageRange: AgeRange = .eighteenToTwenty,
                maxBudget: Double = 25, approximateArea: String = "", availability: CalendarBusyInterval,
                busyIntervals: [CalendarBusyInterval] = [], calendarConnectionStatus: String = "manual") {
        self.id = id; self.displayName = displayName; self.ageRange = ageRange; self.maxBudget = maxBudget
        self.approximateArea = approximateArea; self.availability = availability
        self.busyIntervals = busyIntervals; self.calendarConnectionStatus = calendarConnectionStatus
    }

    public var isValid: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && displayName.count <= 60 &&
        !approximateArea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && approximateArea.count <= 120 &&
        maxBudget.isFinite && (0...500).contains(maxBudget) && availability.duration >= 90 * 60 && availability.duration <= 7 * 86400
    }

    public static func groupBudget(_ participants: [Participant]) -> Double? { participants.map(\.maxBudget).min() }
}

public enum DemoData {
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
                        calendarConnectionStatus: "demo")
        }
    }
}
