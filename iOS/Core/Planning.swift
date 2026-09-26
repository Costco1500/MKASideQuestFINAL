import Foundation

public enum APIJSON {
    public static var encoder: JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
    public static var decoder: JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
}

public struct PlanningParticipant: Codable, Equatable, Sendable {
    public var id: String
    public var ageRange: AgeRange
    public var maxBudget: Double
    public var approximateArea: String
    public var availability: [CalendarBusyInterval]
}

public struct PlanningRequest: Codable, Equatable, Sendable {
    public var participants: [PlanningParticipant]
    public var selectedMessages: [SelectedMessage]
    public var candidateTimeWindows: [CalendarBusyInterval]
    public var timeZone: String

    public init(participants: [Participant], messages: [ImportedMessage], now: Date = Date(), calendar: Calendar = .current) {
        self.participants = participants.map {
            PlanningParticipant(id: $0.id, ageRange: $0.ageRange, maxBudget: $0.maxBudget, approximateArea: $0.approximateArea,
                                availability: AvailabilityEngine.freeWindows(busy: $0.busyIntervals, range: $0.availability))
        }
        selectedMessages = MessageImport.analysisMessages(messages)
        timeZone = calendar.timeZone.identifier
        candidateTimeWindows = participants.first.map {
            AvailabilityEngine.bestTimes(participants, range: $0.availability, now: now, calendar: calendar).map(\.window)
        } ?? []
    }
}

public struct PlanOption: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var activity: String
    public var secondStop: String?
    public var start: Date
    public var end: Date
    public var area: String
    public var estimatedCostPerPerson: Double
    public var explanation: String
    public var whyItWorks: [String: String]
    public var concerns: [String]
    public var minimumAge: Int
    public var groupFitScore: Double
    public var venueSearchQuery: String? = nil
    public var venue: PlanVenue? = nil
    public var calendarLocation: String {
        guard let venue else { return area }
        return [venue.name, venue.address].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

public struct PlanResponse: Codable, Equatable, Sendable {
    public var plans: [PlanOption]
    public var source: String
    public init(plans: [PlanOption], source: String) { self.plans = plans; self.source = source }
}

public enum PlanRules {
    public static func isEligible(_ plan: PlanOption, for request: PlanningRequest) -> Bool {
        guard !request.participants.isEmpty, !plan.id.isEmpty, !plan.title.isEmpty, !plan.activity.isEmpty,
              !plan.explanation.isEmpty, plan.end.timeIntervalSince(plan.start) >= 5400,
              plan.estimatedCostPerPerson.isFinite, plan.estimatedCostPerPerson >= 0,
              (plan.venue?.isValid ?? true), plan.groupFitScore.isFinite, (0...100).contains(plan.groupFitScore), plan.minimumAge >= 0,
              request.participants.contains(where: { $0.approximateArea == plan.area }),
              request.candidateTimeWindows.contains(where: { $0.start <= plan.start && $0.end >= plan.end }) else { return false }
        return request.participants.allSatisfy { person in
            plan.estimatedCostPerPerson <= person.maxBudget && plan.minimumAge <= person.ageRange.minimumEligibleAge &&
            person.availability.contains(where: { $0.start <= plan.start && $0.end >= plan.end }) &&
            !(plan.whyItWorks[person.id] ?? "").isEmpty
        }
    }
    public static func validate(_ plans: [PlanOption], for request: PlanningRequest) -> Bool {
        plans.count == 3 && Set(plans.map(\.id)).count == 3 && plans.allSatisfy { isEligible($0, for: request) }
    }
}

public enum PlanningError: LocalizedError {
    case noAvailability, invalidResponse, invalidServer
    public var errorDescription: String? {
        switch self {
        case .noAvailability: return "No shared 90-minute window. Update availability and try again."
        case .invalidResponse: return "The server returned an invalid response. Please try again."
        case .invalidServer: return "Use an HTTPS server address, or localhost for a simulator demo."
        }
    }
}

public enum DemoPlanner {
    public static func plans(for request: PlanningRequest) throws -> [PlanOption] {
        guard let window = request.candidateTimeWindows.first, let first = request.participants.first,
              let budget = request.participants.map(\.maxBudget).min(), window.duration >= 5400 else { throw PlanningError.noAvailability }
        let titles = budget < 10 ? ["Sketch & stroll", "Bring-your-own picnic", "Neighborhood photo walk"] : ["Clay & boba", "Park picnic", "Gallery & dessert"]
        let activities = budget < 10 ? ["Sketch outdoors with supplies you own", "Bring snacks from home and relax in the park", "Find interesting architecture on a photo walk"] : ["Try a small air-dry clay craft together", "Pack a casual picnic and a card game", "Visit a free public gallery, then find a sweet treat"]
        return titles.enumerated().map { index, title in
            PlanOption(id: "plan-\(index + 1)", title: title, activity: activities[index], secondStop: nil,
                       start: window.start, end: min(window.end, window.start.addingTimeInterval(7200)), area: first.approximateArea,
                       estimatedCostPerPerson: budget < 10 ? 0 : [12.0, 8, 10][index],
                       explanation: "A relaxed option within the group's budget and shared free time.",
                       whyItWorks: Dictionary(uniqueKeysWithValues: request.participants.map { ($0.id, "Fits your available time and comfortable budget.") }),
                       concerns: ["Demo suggestion. Check opening hours, access, weather, and prices before going."], minimumAge: 0, groupFitScore: Double(90 - index),
                       venueSearchQuery: ["art supply store", "public park", "art gallery"][index])
        }
    }
}

public enum PlanGenerator {
    public static func generate(_ request: PlanningRequest,
                                remote: ((PlanningRequest) async throws -> PlanResponse)? = nil) async throws -> PlanResponse {
        guard !request.candidateTimeWindows.isEmpty else { throw PlanningError.noAvailability }
        if let remote, let response = try? await remote(request), PlanRules.validate(response.plans, for: request) { return response }
        let plans = try DemoPlanner.plans(for: request)
        guard PlanRules.validate(plans, for: request) else { throw PlanningError.invalidResponse }
        return PlanResponse(plans: plans, source: "demo")
    }
}

public struct APIClient: Sendable {
    public let baseURL: URL
    public init(baseURL: URL) throws {
        guard baseURL.user == nil, baseURL.password == nil, baseURL.query == nil, baseURL.fragment == nil,
              baseURL.scheme == "https" || (baseURL.scheme == "http" && ["localhost", "127.0.0.1"].contains(baseURL.host ?? "")),
              baseURL.host != nil else { throw PlanningError.invalidServer }
        self.baseURL = baseURL
    }
    public func request<Response: Decodable, Body: Encodable>(_ path: String, method: String = "POST", body: Body, token: String? = nil) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method; request.timeoutInterval = 30
        if method != "GET" { request.httpBody = try APIJSON.encoder.encode(body) }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count <= 1_000_000 else { throw PlanningError.invalidResponse }
        return try APIJSON.decoder.decode(Response.self, from: data)
    }
    public func plan(_ request: PlanningRequest) async throws -> PlanResponse { try await self.request("sidequest/plan", body: request) }
}
