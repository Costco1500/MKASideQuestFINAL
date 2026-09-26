import Foundation

/// Small geometry heuristics for user-reviewed screenshot text, not a claim of perfect chat reconstruction.
public enum ScreenshotMessageParser {
    public static func parse(_ blocks: [OCRTextBlock], participantNames: [String] = []) -> [ImportedMessage] {
        let names = participantNames.reduce(into: [String: String]()) { result, name in
            let trimmed = MessageImport.normalizedWhitespace(name)
            if !trimmed.isEmpty { result[trimmed.lowercased()] = trimmed }
        }
        let screenshots = Dictionary(grouping: blocks, by: \.screenshotIndex)
        var combined: [ImportedMessage] = []
        for index in screenshots.keys.sorted() {
            let sorted = screenshots[index, default: []].sorted {
                if $0.boundingBox.midY == $1.boundingBox.midY {
                    return $0.boundingBox.minX < $1.boundingBox.minX
                }
                return $0.boundingBox.midY > $1.boundingBox.midY
            }
            let messages = reconstruct(sorted, names: names)
            let overlap = longestOverlap(combined, messages)
            for message in messages.dropFirst(overlap) {
                if combined.last.map(key) != key(message) { combined.append(message) }
            }
        }
        MessageImport.select(.latest50, in: &combined)
        return combined
    }

    private static func reconstruct(_ blocks: [OCRTextBlock], names: [String: String]) -> [ImportedMessage] {
        var messages: [ImportedMessage] = []
        var previousBounds: CGRect?
        var pendingLabel: (name: String, bounds: CGRect)?
        for block in blocks {
            let text = MessageImport.normalizedWhitespace(block.text)
            guard !text.isEmpty else { continue }
            let label = text.hasSuffix(":") ? String(text.dropLast()) : text
            if let name = names[label.lowercased()] {
                pendingLabel = (name, block.boundingBox)
                previousBounds = nil
                continue
            }

            let inline = inlineMessage(text, names: names)
            let closeToLabel = pendingLabel.map {
                let gap = $0.bounds.minY - block.boundingBox.maxY
                return gap >= -0.03 && gap < 0.09
            } ?? false
            let sender = inline?.sender ?? (closeToLabel ? pendingLabel?.name : nil) ?? "Unknown"
            let body = inline?.text ?? text
            let canAppend = previousBounds.map { previous in
                let gap = previous.minY - block.boundingBox.maxY
                let sameSide = (previous.midX < 0.5) == (block.boundingBox.midX < 0.5)
                let aligned = abs(previous.minX - block.boundingBox.minX) < 0.06
                return sameSide && aligned && gap >= -0.008 && gap < 0.023
            } ?? false

            if inline == nil, pendingLabel == nil, canAppend, !messages.isEmpty {
                messages[messages.count - 1].text += " " + body
            } else {
                messages.append(ImportedMessage(sender: sender, text: body))
            }
            pendingLabel = nil
            previousBounds = block.boundingBox
        }
        return messages.reduce(into: []) { result, message in
            if result.last.map(key) != key(message) { result.append(message) }
        }
    }

    private static func inlineMessage(_ text: String, names: [String: String]) -> (sender: String, text: String)? {
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let candidate = MessageImport.normalizedWhitespace(String(parts[0]))
        let body = MessageImport.normalizedWhitespace(String(parts[1]))
        guard !candidate.isEmpty, candidate.count <= 60, !body.isEmpty,
              candidate.split(separator: " ").count <= 3,
              candidate.allSatisfy({ $0.isLetter || $0.isWhitespace || $0 == "-" || $0 == "'" }) else { return nil }
        let known = names[candidate.lowercased()]
        guard known != nil || candidate.split(separator: " ").allSatisfy({ $0.first?.isUppercase == true }),
              !body.hasPrefix("//") else { return nil }
        return (known ?? candidate, body)
    }

    private static func key(_ message: ImportedMessage) -> String {
        MessageImport.normalizedWhitespace(message.sender).lowercased() + "\n" +
            MessageImport.normalizedWhitespace(message.text).lowercased()
    }

    private static func longestOverlap(_ previous: [ImportedMessage], _ next: [ImportedMessage]) -> Int {
        let maximum = min(previous.count, next.count)
        guard maximum > 0 else { return 0 }
        for count in stride(from: maximum, through: 1, by: -1) {
            if previous.suffix(count).map(key) == next.prefix(count).map(key) { return count }
        }
        return 0
    }
}
