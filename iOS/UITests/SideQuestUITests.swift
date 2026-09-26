import XCTest

final class SideQuestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    func testProfileAndServerSettingsAreAvailableInContainingApp() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Set up my profile"].tap()
        XCTAssertTrue(app.textFields["Display name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Your comfortable maximum"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.textFields["https://your-sidequest-api.example"].waitForExistence(timeout: 5))
        app.buttons["Save server"].tap()
        app.buttons["Use local demo server"].tap()
        app.buttons["Save server"].tap()
        XCTAssertTrue(app.staticTexts["Server saved."].exists)
        app.buttons["Done"].tap()
    }
    func testMessagesProvidesOwnContextAndSettings() {
        let messages = openMessagesExtension()
        waitForStableFrame(messages.buttons["Settings"])
        messages.buttons["Settings"].tap()
        XCTAssertTrue(messages.staticTexts["Shared-session server"].waitForExistence(timeout: 5))
        messages.buttons["Done"].tap()
        let start = messages.buttons["Start SideQuest"]
        for _ in 0..<3 where !start.isHittable { messages.swipeUp() }
        waitForStableFrame(start); start.tap()
        XCTAssertTrue(messages.textFields["Display name"].waitForExistence(timeout: 8))
        XCTAssertTrue(messages.staticTexts["Only your own information"].exists)
        messages.buttons["Cancel"].tap()
    }
    func testDemoGeneratesPlansAndAcceptsVote() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Try Demo"].tap()
        readDemoChat(in: app)
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
        waitForStableFrame(messages.buttons["Try Demo"])
        messages.buttons["Try Demo"].tap()
        readDemoChat(in: messages)
        waitForStableFrame(messages.buttons["generatePlans"])
        messages.buttons["generatePlans"].tap()
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 10))
        let insert = messages.buttons["Insert poll into Messages"]
        for _ in 0..<8 where !insert.isHittable { messages.swipeUp() }
        waitForStableFrame(insert)
        insert.tap()
        XCTAssertTrue(messages.buttons["Send"].waitForExistence(timeout: 8))
        let screenshot = XCTAttachment(screenshot: messages.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        messages.buttons["Remove app from message"].tap()
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
    func testMessagesWinnerOffersCalendarAndShare() {
        let messages = openMessagesExtension()
        waitForStableFrame(messages.buttons["Try Demo"]); messages.buttons["Try Demo"].tap()
        readDemoChat(in: messages)
        waitForStableFrame(messages.buttons["generatePlans"]); messages.buttons["generatePlans"].tap()
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 8))
        let vote = messages.buttons["vote-plan-1-down"]
        for _ in 0..<5 where !vote.isHittable { messages.swipeUp() }
        waitForStableFrame(vote); vote.tap()
        let finalize = messages.buttons["finalize"]
        for _ in 0..<8 where !finalize.isHittable { messages.swipeUp() }
        waitForStableFrame(finalize); finalize.tap()
        let calendar = messages.buttons["Add to Calendar"]
        waitForStableFrame(calendar); calendar.tap()
        XCTAssertTrue(messages.buttons["Cancel"].waitForExistence(timeout: 10))
        let screenshot = XCTAttachment(screenshot: messages.screenshot()); screenshot.lifetime = .keepAlways; add(screenshot)
        messages.buttons["Cancel"].tap()
        if messages.buttons["Discard Changes"].waitForExistence(timeout: 2) { messages.buttons["Discard Changes"].tap() }
        let share = messages.buttons["Share winning plan"]
        waitForStableFrame(share); share.tap()
        XCTAssertTrue(messages.buttons["Send"].waitForExistence(timeout: 8))
        messages.buttons["Remove app from message"].tap()
    }
    private func readDemoChat(in app: XCUIApplication) {
        let analyze = app.buttons["generatePlans"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 8))
        XCTAssertFalse(analyze.isEnabled, "Demo starts with no messages until the chat is read")
        let read = app.buttons["readChat"]
        for _ in 0..<3 where !read.isHittable { app.swipeUp() }
        waitForStableFrame(read); read.tap()
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Analyze 8 selected messages"), object: analyze)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 8), .completed)
    }
    private func waitForStableFrame(_ element: XCUIElement) {
        var previous = CGRect.null
        var stable = 0
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists else { return false }
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
