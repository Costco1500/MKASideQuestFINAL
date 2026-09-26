import Foundation
import EventKit

@MainActor public protocol CalendarProvider {
    func requestAccess() async throws
    func busyIntervals(from start: Date, to end: Date) async throws -> [CalendarBusyInterval]
}

public enum CalendarAccessError: LocalizedError {
    case denied
    public var errorDescription: String? { "Calendar access is off. Enter your available time manually, or allow full calendar access in Settings." }
}

@MainActor public final class EventKitCalendarProvider: CalendarProvider {
    private let store: EKEventStore
    public init(store: EKEventStore = EKEventStore()) { self.store = store }
    public func requestAccess() async throws {
        guard try await store.requestFullAccessToEvents() else { throw CalendarAccessError.denied }
    }
    public func busyIntervals(from start: Date, to end: Date) async throws -> [CalendarBusyInterval] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw CalendarAccessError.denied }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        // Discard event objects here: titles, notes, attendees, and locations never leave this provider.
        let intervals = store.events(matching: predicate).filter { $0.availability != .free && $0.status != .canceled }
            .map { CalendarBusyInterval(start: max(start, $0.startDate), end: min(end, $0.endDate)) }
        return AvailabilityEngine.normalize(intervals)
    }
}
