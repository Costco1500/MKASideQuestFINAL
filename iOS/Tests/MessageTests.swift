import XCTest
@testable import SideQuestCore

final class MessageTests: XCTestCase {
    func testParserPreservesColonsAndIgnoresBlankLines() {
        let messages = MessageImport.parse(" Jake: Meet at 6:30\n\nMaya: pottery!\nUnattributed text")
        XCTAssertEqual(messages.map(\.sender), ["Jake", "Maya", "Someone"])
        XCTAssertEqual(messages.map(\.text), ["Meet at 6:30", "pottery!", "Unattributed text"])
        XCTAssertTrue(messages.allSatisfy { !$0.isSelected })
        XCTAssertEqual(MessageImport.parse("\n  "), [])
    }
    func testLatest50SelectsOnlyLatestImportedMessages() {
        var messages = MessageImport.parse((0..<65).map { "A: message \($0)" }.joined(separator: "\n"))
        MessageImport.select(.latest50, in: &messages)
        XCTAssertEqual(messages.filter(\.isSelected).count, 50)
        XCTAssertFalse(messages[14].isSelected)
        XCTAssertTrue(messages[15].isSelected)
        MessageImport.select(.clear, in: &messages)
        XCTAssertTrue(messages.allSatisfy { !$0.isSelected })
        MessageImport.select(.all, in: &messages)
        XCTAssertEqual(messages.filter(\.isSelected).count, 65)
    }
    func testAnalysisPayloadExcludesUnselectedAndDeduplicates() {
        var messages = MessageImport.parse("A: pottery\nA: pottery\nB: private text")
        messages[0].isSelected = true; messages[1].isSelected = true
        XCTAssertEqual(MessageImport.analysisMessages(messages).map(\.text), ["pottery"])
        XCTAssertFalse(String(data: try! JSONEncoder().encode(MessageImport.analysisMessages(messages)), encoding: .utf8)!.contains("private text"))
    }
    func testPayloadCapsAt50AndImportBoundsSize() {
        var messages = MessageImport.parse((0..<700).map { "A: \($0)" }.joined(separator: "\n"))
        XCTAssertEqual(messages.count, 500)
        MessageImport.select(.all, in: &messages)
        XCTAssertEqual(MessageImport.analysisMessages(messages).count, 50)
        XCTAssertEqual(MessageImport.analysisMessages(messages).last?.text, "699")
    }
}
