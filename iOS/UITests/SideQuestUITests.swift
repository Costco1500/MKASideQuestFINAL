import XCTest

final class SideQuestUITests: XCTestCase {
    func testMessagesExtensionOpens() {
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        if !messages.buttons["add"].exists, messages.cells.firstMatch.waitForExistence(timeout: 8) { messages.cells.firstMatch.tap() }
        let add = messages.buttons["add"]
        if add.exists { add.tap() }
        let quest = messages.staticTexts["SideQuest"].firstMatch
        for _ in 0..<3 where !quest.exists { messages.swipeUp() }
        if quest.waitForExistence(timeout: 4) { quest.tap() }
        XCTAssertTrue(messages.staticTexts["Your next hangout starts here."].waitForExistence(timeout: 10))
    }
    func testContainingAppExplainsMessagesEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["You choose what SideQuest sees."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Find SideQuest in Messages"].exists)
    }
}
