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

/// Real places near Georgia Tech and Midtown for the curated plans, as listed in Apple Maps in September 2026.
/// The demo shows them without a lookup; the place ID only lets Maps open each business's own page.
public enum DemoVenues {
    public static let glazeTea = PlanVenue(name: "Glaze Tea", address: "960 Spring St NW, Atlanta, GA 30309",
                                           latitude: 33.78081, longitude: -84.38929, placeID: "I7B0061422F5DEC63")
    public static let piedmontPark = PlanVenue(name: "Piedmont Park", address: "1320 Monroe Dr NE, Atlanta, GA 30306",
                                               latitude: 33.78728, longitude: -84.37208, placeID: "I4C670C799ADD7DA4")
    public static let atlantaContemporary = PlanVenue(name: "Atlanta Contemporary", address: "535 Means St NW, Atlanta, GA 30318",
                                                      latitude: 33.77294, longitude: -84.40531, placeID: "I1AA7244113AD17B9")
}

public enum DemoPlanner {
    public static func plans(for request: PlanningRequest) throws -> [PlanOption] {
        guard let window = request.candidateTimeWindows.first, let first = request.participants.first,
              let budget = request.participants.map(\.maxBudget).min(), window.duration >= 5400 else { throw PlanningError.noAvailability }
        let titles = budget < 10 ? ["Sketch & stroll", "Bring-your-own picnic", "Neighborhood photo walk"] : ["Clay & Boba", "Sunset Picnic + Cards", "Gallery + Dessert"]
        let activities = budget < 10 ? ["Sketch outdoors with supplies you own", "Bring snacks from home and relax in the park", "Find interesting architecture on a photo walk"] : ["Make something a little wonky. Grab boba after.", "Bring snacks, a deck of cards, and absolutely no agenda.", "A little art, a sweet treat, and room to catch up."]
        let seven = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0, of: window.start)!
        let start = seven >= window.start && seven.addingTimeInterval(7200) <= window.end ? seven : window.start
        let fits = [
            ["alex": "You suggested boba. We heard you.", "maya": "You wanted pottery — start with an easy air-dry clay craft.", "jake": "About $12 keeps it below your $15 chat budget.", "sarah": "A small, quiet hangout without the restaurant crowd."],
            ["alex": "Plenty of time after your 6:30 lab.", "maya": "A relaxed break from your laptop.", "jake": "An $8 plan leaves breathing room this week.", "sarah": "Space to talk, with no loud restaurant."],
            ["alex": "An easy evening after class, with something sweet.", "maya": "A dose of creativity without a whole class.", "jake": "About $10, comfortably inside your budget.", "sarah": "An indoor option with time to catch up."]
        ]
        let venues = budget < 10 ? [DemoVenues.piedmontPark, DemoVenues.piedmontPark, DemoVenues.atlantaContemporary]
                                 : [DemoVenues.glazeTea, DemoVenues.piedmontPark, DemoVenues.atlantaContemporary]
        let secondStops: [String?] = budget < 10 ? [nil, nil, nil] : [nil, nil, "Insomnia Cookies · 930 Spring St NW"]
        let tips: [[String]] = budget < 10 ? [[], [], []] : [
            ["Grab air-dry clay beforehand at Blick Art Materials, 878 Peachtree St NE.", "Glaze Tea is open until 10 PM."],
            ["Bring a blanket, snacks, and a deck of cards."],
            ["Atlanta Contemporary is free and open until 8 PM on Thursdays."]
        ]
        return titles.enumerated().map { index, title in
            PlanOption(id: "plan-\(index + 1)", title: title, activity: activities[index], secondStop: secondStops[index],
                       start: start, end: min(window.end, start.addingTimeInterval(7200)), area: first.approximateArea,
                       estimatedCostPerPerson: budget < 10 ? 0 : [12.0, 8, 10][index],
                       explanation: ["Creative · quiet · everyone available", "Relaxed · inexpensive · easy for everyone", "Indoor · casual · time to reconnect"][index],
                       whyItWorks: Dictionary(uniqueKeysWithValues: request.participants.map { ($0.id, fits[index][$0.id] ?? "Fits your available time and comfortable budget.") }),
                       concerns: tips[index] + ["Real place, curated for this demo. Nothing is booked; check hours and prices before you go."],
                       minimumAge: 0, groupFitScore: Double(90 - index),
                       venueSearchQuery: ["art supply store", "public park", "art gallery"][index],
                       venue: venues[index])
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
