import Foundation

/// Weekly hours parsed from the common subset of OpenStreetMap's `opening_hours` syntax,
/// e.g. `Mo-Th,Su 11:00-24:00; Fr-Sa 11:00-02:00`. Anything outside that subset is rejected
/// so an unfamiliar rule is reported as unknown instead of guessed.
public struct OpeningHours: Equatable, Sendable {
    /// Minutes after local midnight. `close` exceeds 1440 when a venue stays open past midnight.
    public struct Span: Equatable, Sendable {
        public var open: Int
        public var close: Int
    }
    /// Index 0 is Monday; 6 is Sunday.
    public var week: [[Span]]

    private static let dayCodes = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    public init?(osm raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 255 else { return nil }
        if text == "24/7" { week = Array(repeating: [Span(open: 0, close: 1440)], count: 7); return }
        var week = Array(repeating: [Span](), count: 7)
        for rule in Self.rules(text) {
            guard let parsed = Self.parse(rule) else { return nil }
            // Holiday-only rules don't change the regular week.
            guard let days = parsed.days else { continue }
            for day in days { week[day] = parsed.spans }
        }
        guard week.contains(where: { !$0.isEmpty }) else { return nil }
        self.week = week
    }

    /// Splits `;` rules and `, ` additional rules, keeping `Mo, We 10:00-12:00` and
    /// `10:00-14:00, 17:00-22:00` together.
    private static func rules(_ text: String) -> [String] {
        var result: [String] = []
        for part in text.split(separator: ";") {
            let partStart = result.count
            var pending = ""
            for raw in part.components(separatedBy: ", ") {
                let piece = raw.trimmingCharacters(in: .whitespaces)
                let joined = pending.isEmpty ? piece : pending + "," + piece
                pending = ""
                if !piece.contains(" "), daySet(piece) != nil { pending = joined; continue }
                if joined == piece, piece.first?.isNumber == true, result.count > partStart {
                    result[result.count - 1] += "," + piece
                } else { result.append(joined) }
            }
            if !pending.isEmpty { result.append(pending) }
        }
        return result.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// `days == nil` marks a public/school holiday rule that is safe to skip.
    private static func parse(_ rule: String) -> (days: [Int]?, spans: [Span])? {
        var words = rule.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        if words[0].hasPrefix("PH") || words[0].hasPrefix("SH") { return (nil, []) }
        var days = Array(0..<7)
        if let selected = daySet(words[0]) { days = selected; words.removeFirst() }
        let times = words.joined()
        guard !times.isEmpty else { return nil }
        if times == "off" || times == "closed" { return (days, []) }
        var spans: [Span] = []
        for range in times.split(separator: ",") {
            let ends = range.split(separator: "-")
            guard ends.count == 2, let open = minutes(ends[0]), let close = minutes(ends[1]), open < 1440 else { return nil }
            spans.append(Span(open: open, close: close <= open ? close + 1440 : close))
        }
        return (days, spans.sorted { $0.open < $1.open })
    }

    private static func daySet(_ token: String) -> [Int]? {
        var days: [Int] = []
        for item in token.split(separator: ",") where item != "PH" && item != "SH" {
            let ends = item.split(separator: "-").map(String.init)
            guard (1...2).contains(ends.count), let first = dayCodes.firstIndex(of: ends[0]) else { return nil }
            guard ends.count == 2 else { days.append(first); continue }
            guard let last = dayCodes.firstIndex(of: ends[1]) else { return nil }
            var day = first
            while true { days.append(day); if day == last { break }; day = (day + 1) % 7 }
        }
        return days.isEmpty ? nil : days
    }

    private static func minutes(_ value: Substring) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, parts[0].count <= 2, parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]), (0...24).contains(hour), (0..<60).contains(minute),
              hour < 24 || minute == 0 else { return nil }
        return hour * 60 + minute
    }

    /// Whether the venue is open for the whole plan, in the device's local time.
    public func status(from start: Date, to end: Date, calendar: Calendar = .current) -> VenueHoursStatus {
        guard end > start else { return .unknown }
        let midnight = calendar.startOfDay(for: start)
        let today = (calendar.component(.weekday, from: start) + 5) % 7
        // Yesterday's late hours spill into today; tomorrow's early hours matter for late plans.
        var spans = week[(today + 6) % 7].filter { $0.close > 1440 }.map { Span(open: 0, close: $0.close - 1440) }
        spans += week[today]
        spans += week[(today + 1) % 7].map { Span(open: $0.open + 1440, close: $0.close + 1440) }
        var merged: [Span] = []
        for span in spans.sorted(by: { $0.open < $1.open }) {
            if let last = merged.last, span.open <= last.close { merged[merged.count - 1].close = max(last.close, span.close) }
            else { merged.append(span) }
        }
        let from = Int(start.timeIntervalSince(midnight) / 60)
        let to = from + Int((end.timeIntervalSince(start) / 60).rounded(.up))
        func date(_ minutes: Int) -> Date { midnight.addingTimeInterval(TimeInterval(minutes * 60)) }
        if let span = merged.first(where: { $0.open <= from && $0.close >= to }) {
            return .open(until: date(span.close), allDay: span.close - span.open >= 2880)
        }
        if let span = merged.first(where: { $0.open <= from && $0.close > from }) { return .closesEarly(at: date(span.close)) }
        if let span = merged.first(where: { $0.open > from && $0.open < to }) { return .opensLate(at: date(span.open)) }
        return .closed
    }
}

public enum VenueHoursStatus: Equatable, Sendable {
    /// Open for the whole plan. `allDay` means the listed hours never close around it.
    case open(until: Date, allDay: Bool)
    case closesEarly(at: Date)
    case opensLate(at: Date)
    case closed
    case unknown

    public var isOpenForWholePlan: Bool { if case .open = self { return true }; return false }
    /// Lower is better when choosing between nearby places for the same plan.
    var preference: Int {
        switch self {
        case .open: return 0
        case .unknown: return 1
        case .closesEarly, .opensLate: return 2
        case .closed: return 3
        }
    }
}

public extension PlanVenue {
    func hoursStatus(from start: Date, to end: Date, calendar: Calendar = .current) -> VenueHoursStatus {
        guard let openingHours, let hours = OpeningHours(osm: openingHours) else { return .unknown }
        return hours.status(from: start, to: end, calendar: calendar)
    }
}

/// Looks up listed opening hours in OpenStreetMap. Only public venue names and
/// coordinates are sent, never participant locations, messages, or tokens.
public enum OpeningHoursDirectory {
    public typealias Lookup = @Sendable ([PlanVenue]) async -> [String?]

    public static let live: Lookup = { venues in
        let none = venues.map { _ in String?.none }
        guard !venues.isEmpty, venues.count <= 20 else { return none }
        let arounds = venues.map { String(format: "nwr(around:150,%.5f,%.5f)[\"opening_hours\"][\"name\"];", $0.latitude, $0.longitude) }
        var components = URLComponents(string: "https://overpass-api.de/api/interpreter")!
        components.queryItems = [URLQueryItem(name: "data", value: "[out:json][timeout:10];(" + arounds.joined() + ");out tags center 200;")]
        guard let url = components.url else { return none }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("SideQuest/1.0 (iOS group planner)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let result = try? JSONDecoder().decode(OverpassResult.self, from: data) else { return none }
        return venues.map { match($0, in: result.elements) }
    }

    struct OverpassResult: Decodable { var elements: [Element] }
    struct Element: Decodable {
        var lat: Double?
        var lon: Double?
        var center: Center?
        var tags: [String: String]?
        struct Center: Decodable { var lat: Double; var lon: Double }
        var latitude: Double? { lat ?? center?.lat }
        var longitude: Double? { lon ?? center?.lon }
    }

    /// Picks the closest mapped place with the same name within 200 m.
    static func match(_ venue: PlanVenue, in elements: [Element]) -> String? {
        let wanted = normalized(venue.name)
        let candidates = elements.compactMap { element -> (Double, String)? in
            // The server only accepts 1–255 visible characters, the same limit OpenStreetMap uses.
            guard let tags = element.tags, let hours = tags["opening_hours"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  (1...255).contains(hours.count), let name = tags["name"],
                  let latitude = element.latitude, let longitude = element.longitude,
                  sameName(wanted, normalized(name)) else { return nil }
            let distance = metres(venue.latitude, venue.longitude, latitude, longitude)
            return distance <= 200 ? (distance, hours) : nil
        }
        return candidates.min { $0.0 < $1.0 }?.1
    }

    static func normalized(_ name: String) -> [String] {
        name.lowercased().replacingOccurrences(of: "&", with: " and ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "the" }
    }

    static func sameName(_ a: [String], _ b: [String]) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        let left = a.joined(separator: " "), right = b.joined(separator: " ")
        if min(left.count, right.count) >= 4, left.contains(right) || right.contains(left) { return true }
        return Double(Set(a).intersection(b).count) / Double(Set(a).union(b).count) >= 0.6
    }

    private static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let x = (lon2 - lon1) * radians * cos((lat1 + lat2) / 2 * radians)
        let y = (lat2 - lat1) * radians
        return (x * x + y * y).squareRoot() * 6_371_000
    }
}
