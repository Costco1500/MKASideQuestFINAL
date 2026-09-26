import Foundation

/// A single, replaceable handoff containing text only. Images never enter this store.
public struct SharedImportStore {
    public static let appGroup = "group.com.sidequest.shared"
    private let directory: URL?
    public init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)) {
        self.directory = directory
    }
    private var file: URL {
        get throws {
            guard let directory else { throw ImportError.unavailableGroup }
            return directory.appendingPathComponent("pending-conversation.json")
        }
    }
    public var hasPendingImport: Bool { (try? loadImportedMessages().isEmpty) == false }
    public func saveImportedMessages(_ messages: [ImportedMessage]) throws {
        let destination = try file
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bounded = Array(messages.suffix(500)).map { message in
            var result = message
            result.sender = String(result.sender.prefix(60)); result.text = String(result.text.prefix(2000))
            return result
        }
        try JSONEncoder().encode(bounded).write(to: destination, options: [.atomic, .completeFileProtectionUnlessOpen])
    }
    public func loadImportedMessages() throws -> [ImportedMessage] {
        let source = try file
        guard FileManager.default.fileExists(atPath: source.path) else { return [] }
        return try JSONDecoder().decode([ImportedMessage].self, from: Data(contentsOf: source))
    }
    public func clearImportedMessages() throws {
        let source = try file
        if FileManager.default.fileExists(atPath: source.path) { try FileManager.default.removeItem(at: source) }
    }
    private enum ImportError: LocalizedError {
        case unavailableGroup
        var errorDescription: String? { "Shared storage is unavailable. Enable the SideQuest App Group for all three app targets." }
    }
}
