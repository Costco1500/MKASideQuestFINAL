import XCTest

final class SideQuestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testDemoGeneratesPlansAndAcceptsVote() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Try Demo"].tap()
        app.buttons["generatePlans"].tap()
        XCTAssertTrue(app.staticTexts["Make it a group yes."].waitForExistence(timeout: 10))
        let vote = app.buttons["vote-plan-1-down"]
        for _ in 0..<5 where !vote.isHittable { app.swipeUp() }
        vote.tap()
        XCTAssertEqual(vote.value as? String, "Selected")
        let finalize = app.buttons["finalize"]
        for _ in 0..<8 where !finalize.isHittable { app.swipeUp() }
        waitForStableFrame(finalize)
        finalize.tap()
        XCTAssertTrue(app.staticTexts["SideQuest set 🎉"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Add to Calendar"].waitForExistence(timeout: 5))
        app.buttons["Add to Calendar"].tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: app.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["Cancel"].tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 2) { app.buttons["Discard Changes"].tap() }
    }
    func testMessagesExtensionOpens() {
        let messages = openMessagesExtension()
        XCTAssertTrue(messages.staticTexts["Your next hangout starts here."].waitForExistence(timeout: 10))
    }
    func testMessagesPollInsertsWithoutSending() {
        let messages = openMessagesExtension()
        messages.buttons["Try Demo"].tap()
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            messages.buttons["generatePlans"].isHittable && messages.buttons["generatePlans"].frame.minY > 700
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 8), .completed)
        messages.buttons["generatePlans"].tap()
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 10))
        let insert = messages.buttons["Insert poll into Messages"]
        for _ in 0..<8 where !insert.isHittable { messages.swipeUp() }
        waitForStableFrame(insert)
        insert.tap()
        XCTAssertTrue(messages.buttons["Send"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: messages.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func openMessagesExtension() -> XCUIApplication {
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS")
        messages.launch()
        if !messages.buttons["add"].exists, messages.cells.firstMatch.waitForExistence(timeout: 8) { messages.cells.firstMatch.tap() }
        let add = messages.buttons["add"]
        if add.exists { add.tap() }
        let quest = messages.staticTexts["SideQuest"].firstMatch
        for _ in 0..<3 where !quest.exists { messages.swipeUp() }
        if quest.waitForExistence(timeout: 4) { quest.tap() }
        return messages
    }
    private func waitForStableFrame(_ element: XCUIElement) {
        var previous = CGRect.null
        var stable = 0
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = element.frame
            stable = element.isHittable && frame == previous ? stable + 1 : 0
            previous = frame
            return stable >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    func testContainingAppExplainsMessagesEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["You choose what SideQuest sees."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Find SideQuest in Messages"].exists)
    }
}
