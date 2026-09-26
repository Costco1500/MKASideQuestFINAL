import Foundation

public struct ImportedMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String = UUID().uuidString
    public var sender: String
    public var text: String
    public var timestamp: Date? = nil
    public var isSelected = false
}

public struct SelectedMessage: Codable, Equatable, Sendable {
    public var sender: String
    public var text: String
}

public enum MessageImport {
    public enum Selection { case all, clear, latest50 }
    public static func parse(_ text: String) -> [ImportedMessage] {
        text.prefix(100_000).components(separatedBy: .newlines).compactMap { line -> ImportedMessage? in
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            let pieces = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let hasSender = pieces.count == 2 && !pieces[0].isEmpty && pieces[0].count <= 60
            let sender = hasSender ? String(pieces[0]).trimmingCharacters(in: .whitespaces) : "Someone"
            let body = hasSender ? String(pieces[1]).trimmingCharacters(in: .whitespaces) : line
            guard !body.isEmpty else { return nil }
            return ImportedMessage(sender: sender, text: String(body.prefix(2000)))
        }.suffix(500).map { $0 }
    }

    public static func select(_ selection: Selection, in messages: inout [ImportedMessage]) {
        for index in messages.indices {
            switch selection {
            case .all: messages[index].isSelected = true
            case .clear: messages[index].isSelected = false
            case .latest50: messages[index].isSelected = index >= max(0, messages.count - 50)
            }
        }
    }

    public static func analysisMessages(_ messages: [ImportedMessage]) -> [SelectedMessage] {
        var seen = Set<String>()
        return messages.filter(\.isSelected).reversed().compactMap { message in
            let key = (message.sender + "\n" + message.text).lowercased()
                .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard seen.insert(key).inserted else { return nil }
            return SelectedMessage(sender: message.sender, text: message.text)
        }.prefix(50).reversed()
    }
}

extension DemoData {
    public static let conversation = """
    Jake: We should do something Thursday.
    Maya: I've wanted to try pottery.
    Sarah: Somewhere not too loud please.
    Alex: Boba after would be fun.
    Jake: I am free after 6.
    Maya: Same.
    Sarah: I can do 5 to 10.
    Alex: After 6:30 works.
    """
}
