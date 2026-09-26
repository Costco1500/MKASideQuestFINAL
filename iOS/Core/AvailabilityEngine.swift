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
        return candidates.sorted {
            let left = calendar.component(.hour, from: $0.start) >= 17
            let right = calendar.component(.hour, from: $1.start) >= 17
            return left == right ? $0.start < $1.start : left
        }.prefix(3).map { $0 }
    }
}
