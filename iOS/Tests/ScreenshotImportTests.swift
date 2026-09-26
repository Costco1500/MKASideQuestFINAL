import XCTest
import UIKit
@testable import SideQuestCore

final class ScreenshotImportTests: XCTestCase {
    private func block(_ text: String, image: Int = 0, y: CGFloat, x: CGFloat = 0.08,
                       height: CGFloat = 0.025) -> OCRTextBlock {
        OCRTextBlock(text: text, boundingBox: CGRect(x: x, y: y, width: 0.55, height: height),
                     screenshotIndex: image)
    }

    func testParserPreservesPickerOrderThenTopToBottomTextOrder() {
        let messages = ScreenshotMessageParser.parse([
            block("Jake: third", image: 1, y: 0.9),
            block("Maya: second", y: 0.5),
            block("Jake: first", y: 0.8)
        ], participantNames: ["Jake", "Maya"])
        XCTAssertEqual(messages.map(\.text), ["first", "second", "third"])
        XCTAssertTrue(messages.allSatisfy(\.isSelected))
    }

    func testStandaloneSenderLabelAndNearbyLinesFormOneMessage() {
        let messages = ScreenshotMessageParser.parse([
            block("Maya", y: 0.9),
            block("I've wanted to try", y: 0.86),
            block("pottery on Thursday", y: 0.82),
            block("Boba after?", y: 0.6, x: 0.4)
        ], participantNames: ["Maya"])
        XCTAssertEqual(messages.map(\.sender), ["Maya", "Unknown"])
        XCTAssertEqual(messages.map(\.text), ["I've wanted to try pottery on Thursday", "Boba after?"])
    }

    func testUnknownSenderTextAndTimeArePreserved() {
        let messages = ScreenshotMessageParser.parse([
            block("6:30 works for me", y: 0.8),
            block("somewhere quiet please", y: 0.6)
        ])
        XCTAssertEqual(messages.map(\.sender), ["Unknown", "Unknown"])
        XCTAssertEqual(messages.map(\.text), ["6:30 works for me", "somewhere quiet please"])
    }

    func testAdjacentNormalizedDuplicatesAreRemovedButDifferentSendersRemain() {
        let messages = ScreenshotMessageParser.parse([
            block("Maya: Pottery   sounds good", y: 0.9),
            block("maya: pottery sounds GOOD", y: 0.7),
            block("Jake: pottery sounds good", y: 0.5)
        ], participantNames: ["Maya", "Jake"])
        XCTAssertEqual(messages.map(\.sender), ["Maya", "Jake"])
    }

    func testOverlappingScreenshotSuffixAndPrefixAreRemoved() {
        let messages = ScreenshotMessageParser.parse([
            block("Jake: one", y: 0.9), block("Maya: two", y: 0.7), block("Alex: three", y: 0.5),
            block("Maya: TWO", image: 1, y: 0.9), block("Alex: three", image: 1, y: 0.7),
            block("Sarah: four", image: 1, y: 0.5)
        ], participantNames: ["Jake", "Maya", "Alex", "Sarah"])
        XCTAssertEqual(messages.map(\.text), ["one", "two", "three", "four"])
    }

    func testEmptyAndWhitespaceOnlyOCRHasNoMessages() {
        XCTAssertTrue(ScreenshotMessageParser.parse([]).isEmpty)
        XCTAssertTrue(ScreenshotMessageParser.parse([block("   \n", y: 0.8)]).isEmpty)
    }

    func testParserDefaultsToLatestFiftyMessages() {
        let blocks = (0..<65).map { block("Jake: message \($0)", image: $0, y: 0.8) }
        let messages = ScreenshotMessageParser.parse(blocks)
        XCTAssertEqual(messages.count, 65)
        XCTAssertEqual(messages.filter(\.isSelected).count, 50)
        XCTAssertEqual(messages.first(where: \.isSelected)?.text, "message 15")
    }

    func testLastTenSelection() { assertSelection(.latest10, count: 10) }
    func testLastTwentyFiveSelection() { assertSelection(.latest25, count: 25) }
    func testLastFiftySelection() { assertSelection(.latest50, count: 50) }

    private func assertSelection(_ selection: MessageImport.Selection, count: Int,
                                 file: StaticString = #filePath, line: UInt = #line) {
        var messages = MessageImport.parse((0..<65).map { "Jake: message \($0)" }.joined(separator: "\n"))
        MessageImport.select(selection, in: &messages)
        XCTAssertEqual(messages.filter(\.isSelected).map(\.text),
                       ((65 - count)..<65).map { "message \($0)" }, file: file, line: line)
    }

    func testSelectedPayloadIsNormalizedCappedAndContainsOnlySenderAndText() throws {
        var messages = MessageImport.parse((0..<65).map { "Jake: message \($0)" }.joined(separator: "\n"))
        MessageImport.select(.all, in: &messages)
        messages.append(ImportedMessage(sender: "  Maya \n", text: "  Let's   get\n boba  ", isSelected: true))
        messages.append(ImportedMessage(sender: "Sarah", text: "PRIVATE UNSELECTED TEXT", isSelected: false))
        let payload = MessageImport.analysisMessages(messages)
        XCTAssertEqual(payload.count, 50)
        XCTAssertEqual(payload.last?.sender, "Maya")
        XCTAssertEqual(payload.last?.text, "Let's get boba")
        let encoded = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [[String: Any]])
        XCTAssertTrue(json.allSatisfy { Set($0.keys) == Set(["sender", "text"]) })
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("PRIVATE"))
    }

    func testDemoFixturesRunActualVisionOCRThenParser() async throws {
        let images = DemoChatScreenshots.images()
        XCTAssertEqual(images.count, 3)
        for (index, image) in images.enumerated() {
            let attachment = XCTAttachment(image: image)
            attachment.name = "sidequest-demo-chat-\(index + 1)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let blocks = try await ChatScreenshotOCRService().recognizeMessages(from: images)
        XCTAssertEqual(Set(blocks.map(\.screenshotIndex)), Set([0, 1, 2]))
        XCTAssertTrue(blocks.allSatisfy { !$0.text.isEmpty && !$0.boundingBox.isEmpty })
        let messages = ScreenshotMessageParser.parse(blocks, participantNames: ["Jake", "Maya", "Sarah", "Alex"])
        XCTAssertEqual(messages.count, 8)
        XCTAssertTrue(messages.contains { $0.sender == "Maya" && $0.text.lowercased().contains("pottery") })
        XCTAssertTrue(messages.contains { $0.sender == "Alex" && $0.text.lowercased().contains("boba") })
    }

    func testCustomDemoScriptAlsoUsesActualVisionOCR() async throws {
        let images = DemoChatScreenshots.images(script: "Maya: Mini golf on Friday\nJake: Tacos after")
        let blocks = try await ChatScreenshotOCRService().recognizeMessages(from: images)
        let messages = ScreenshotMessageParser.parse(blocks, participantNames: ["Maya", "Jake"])
        XCTAssertEqual(messages.map(\.text), ["Mini golf on Friday", "Tacos after"])
    }

    func testEmptyImageSelectionReturnsNoOCRBlocks() async throws {
        let result = try await ChatScreenshotOCRService().recognizeMessages(from: [])
        XCTAssertTrue(result.isEmpty)
    }
}
