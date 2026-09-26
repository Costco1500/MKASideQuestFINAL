import Foundation

public enum AvailabilityEngine {
    public static func normalize(_ intervals: [CalendarBusyInterval]) -> [CalendarBusyInterval] {
        var merged: [CalendarBusyInterval] = []
        for interval in intervals.filter({ $0.duration > 0 }).sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else { merged.append(interval) }
        }
        return merged
    }

    public static func freeWindows(busy: [CalendarBusyInterval], range: CalendarBusyInterval) -> [CalendarBusyInterval] {
        guard range.duration > 0 else { return [] }
        var cursor = range.start
        var free: [CalendarBusyInterval] = []
        for interval in normalize(busy) where interval.end > range.start && interval.start < range.end {
            if interval.start > cursor { free.append(.init(start: cursor, end: min(interval.start, range.end))) }
            cursor = max(cursor, interval.end)
        }
        if cursor < range.end { free.append(.init(start: cursor, end: range.end)) }
        return free
    }

    public static func sharedFreeWindows(_ participants: [Participant], range: CalendarBusyInterval,
                                         minimumDuration: TimeInterval = 5400, calendar: Calendar = .current) -> [CalendarBusyInterval] {
        daytimeWindows(participants, range: range, minimumDuration: minimumDuration, calendar: calendar).sorted {
            let left = calendar.component(.hour, from: $0.start) >= 17
            let right = calendar.component(.hour, from: $1.start) >= 17
            return left == right ? $0.start < $1.start : left
        }.prefix(3).map { $0 }
    }

    /// Every shared free window of at least `minimumDuration`, clipped to 10 AM–11 PM each day.
    private static func daytimeWindows(_ participants: [Participant], range: CalendarBusyInterval,
                                       minimumDuration: TimeInterval, calendar: Calendar) -> [CalendarBusyInterval] {
        guard !participants.isEmpty, minimumDuration > 0, range.duration > 0, range.duration <= 7 * 86400 else { return [] }
        let start = max(range.start, participants.map(\.availability.start).max()!)
        let end = min(range.end, participants.map(\.availability.end).min()!)
        guard start < end else { return [] }
        let free = freeWindows(busy: participants.flatMap(\.busyIntervals), range: .init(start: start, end: end))
        var candidates: [CalendarBusyInterval] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            let opening = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: day)!
            let closing = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day)!
            for window in free {
                let clipped = CalendarBusyInterval(start: max(opening, window.start), end: min(closing, window.end))
                if clipped.duration >= minimumDuration { candidates.append(clipped) }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return candidates
    }

    /// The best times for everyone to meet, best first: one focused slot (at most four hours) per
    /// free window, favoring evenings and weekend afternoons, room to linger, and some notice.
    /// Slots on different days come before a second slot on the same day.
    public static func bestTimes(_ participants: [Participant], range: CalendarBusyInterval, minimumDuration: TimeInterval = 5400,
                                 limit: Int = 3, now: Date? = nil, calendar: Calendar = .current) -> [RankedTimeSlot] {
        var windows = daytimeWindows(participants, range: range, minimumDuration: minimumDuration, calendar: calendar)
        if let now {
            let quarterHours = (now.timeIntervalSinceReferenceDate / 900).rounded(.up)
            let soonest = Date(timeIntervalSinceReferenceDate: quarterHours * 900)
            windows = windows.map { CalendarBusyInterval(start: max($0.start, soonest), end: $0.end) }
                .filter { $0.duration >= minimumDuration }
        }
        let slots = windows.map { bestSlot(in: $0, now: now, calendar: calendar) }.sorted(by: RankedTimeSlot.ranksHigher)
        var chosen: [RankedTimeSlot] = []
        var days = Set<Date>()
        for slot in slots where chosen.count < limit && days.insert(calendar.startOfDay(for: slot.window.start)).inserted {
            chosen.append(slot)
        }
        for slot in slots where chosen.count < limit && !chosen.contains(slot) { chosen.append(slot) }
        return chosen.sorted(by: RankedTimeSlot.ranksHigher)
    }

    private static func bestSlot(in window: CalendarBusyInterval, now: Date?, calendar: Calendar) -> RankedTimeSlot {
        let length = min(window.duration, 4 * 3600)
        var starts = [window.start]
        let firstHalfHour = Date(timeIntervalSinceReferenceDate: (window.start.timeIntervalSinceReferenceDate / 1800).rounded(.up) * 1800)
        var next = firstHalfHour > window.start ? firstHalfHour : firstHalfHour.addingTimeInterval(1800)
        while next.addingTimeInterval(length) <= window.end { starts.append(next); next = next.addingTimeInterval(1800) }
        let hours = window.duration / 3600
        let roomy = hours >= 3 ? 0.1 : (hours >= 2 ? 0.05 : 0)
        let open = (hours * 2).rounded(.down) / 2
        let openLabel = hours >= 6 ? "Wide open" : (open == open.rounded() ? String(Int(open)) : String(format: "%.1f", open)) + " hrs open"
        var best: RankedTimeSlot?
        for start in starts {
            let (fit, label) = timeOfDayFit(start, calendar: calendar)
            var score = fit + roomy
            var reasons = [label, openLabel]
            if let now {
                let notice = start.timeIntervalSince(now)
                if notice < 2 * 3600 { score -= 0.4; reasons.append("Starts soon") } else if notice < 12 * 3600 { score -= 0.05 }
            }
            if best == nil || score > best!.score {
                best = RankedTimeSlot(window: .init(start: start, end: start.addingTimeInterval(length)), score: score, reasons: reasons)
            }
        }
        return best!
    }

    private static func timeOfDayFit(_ date: Date, calendar: Calendar) -> (Double, String) {
        let hour = Double(calendar.component(.hour, from: date)) + Double(calendar.component(.minute, from: date)) / 60
        switch calendar.component(.weekday, from: date) {
        case 7:
            if (18...20).contains(hour) { return (1.0, "Saturday night") }
            if (12...15).contains(hour) { return (0.95, "Weekend afternoon") }
            return (11...21).contains(hour) ? (0.8, "Weekend") : (0.5, "Weekend")
        case 1:
            if (12...15.5).contains(hour) { return (0.95, "Weekend afternoon") }
            return (11...18).contains(hour) ? (0.8, "Sunday") : (0.5, "Sunday")
        case let weekday:
            let friday = weekday == 6
            if (18...19.5).contains(hour) { return friday ? (1.0, "Friday night") : (0.9, "After class & work") }
            if (17...21).contains(hour) { return (friday ? 0.9 : 0.8, "Evening") }
            if (12..<17).contains(hour) { return (0.45, "Daytime") }
            return hour < 12 ? (0.3, "Morning") : (0.35, "Late night")
        }
    }
}

public extension CalendarBusyInterval {
    /// From the next half hour through the following seven days, the widest range a profile allows.
    static func upcomingWeek(from now: Date = Date()) -> CalendarBusyInterval {
        let start = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 1800).rounded(.up) * 1800)
        return CalendarBusyInterval(start: start, end: start.addingTimeInterval(7 * 86400))
    }
    /// Next 5 PM through 10 PM, a sensible single-evening window.
    static func nextEvening(from now: Date = Date(), calendar: Calendar = .current) -> CalendarBusyInterval {
        let start = calendar.nextDate(after: now, matching: DateComponents(hour: 17), matchingPolicy: .nextTime) ?? now
        return CalendarBusyInterval(start: start, end: start.addingTimeInterval(5 * 3600))
    }
    var isUpcomingWeek: Bool { duration >= 6.5 * 86400 }
}

/// A shared free time ranked by how easy it is for the group to actually show up.
public struct RankedTimeSlot: Equatable, Sendable {
    public var window: CalendarBusyInterval
    public var score: Double
    public var reasons: [String]
    /// Higher score first; earlier start breaks ties.
    static func ranksHigher(_ left: RankedTimeSlot, _ right: RankedTimeSlot) -> Bool {
        if left.score != right.score { return left.score > right.score }
        return left.window.start < right.window.start
    }
}
