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
        messages.buttons["Use local demo server"].tap()
        messages.buttons["Save server"].tap()
        messages.buttons["Done"].tap()
        let start = messages.buttons["Start SideQuest"]
        for _ in 0..<3 where !start.isHittable { messages.swipeUp() }
        waitForStableFrame(start); start.tap()
        XCTAssertTrue(messages.buttons["Send"].waitForExistence(timeout: 10))
        messages.buttons["Remove app from message"].tap()
        // Creation inserts an invitation before the host has supplied a profile.
        messages.terminate()
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
    func testMessagesPreloadsRecentGroupChat() {
        let messages = openMessagesExtension(resetSession: false)
        XCTAssertTrue(messages.staticTexts["Recent group chat"].waitForExistence(timeout: 10))
        XCTAssertTrue(messages.buttons["Analyze Recent Chat"].isEnabled)
        XCTAssertTrue(messages.buttons["Choose Messages"].exists)
    }
    private func openMessagesExtension(resetSession: Bool = true) -> XCUIApplication {
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
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Analyze 8 Messages"), object: analyze)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
    }
    func testScreenshotReviewSelectionAndSenderCorrection() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Try Demo"].tap()
        readDemoChat(in: app)
        let clear = app.buttons["Clear"]
        for _ in 0..<5 where !clear.isHittable { app.swipeUp() }
        waitForStableFrame(clear); clear.tap()
        XCTAssertFalse(app.buttons["generatePlans"].isEnabled)
        app.buttons["Last 10"].tap()
        XCTAssertTrue(app.buttons["generatePlans"].isEnabled)
        let sender = app.buttons.matching(identifier: "messageSender").firstMatch
        for _ in 0..<3 where !sender.isHittable { app.swipeUp() }
        waitForStableFrame(sender); sender.tap()
        let unknown = app.buttons["Unknown"].firstMatch
        XCTAssertTrue(unknown.waitForExistence(timeout: 5)); unknown.tap()
        XCTAssertEqual(sender.label, "Unknown")
        let scan = app.buttons["Scan Recent Chat"]
        for _ in 0..<5 where !scan.isHittable { app.swipeDown() }
        waitForStableFrame(scan); scan.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["generatePlans"].isEnabled, "Cancel retains the reviewed selection")
    }
    func testPhotosPickerImportsScreenshots() throws {
        let app = openMessagesExtension()
        waitForStableFrame(app.buttons["Try Demo"]); app.buttons["Try Demo"].tap()
        readDemoChat(in: app)
        let clear = app.buttons["Clear Imported Messages"]
        for _ in 0..<10 where !clear.isHittable { app.swipeUp() }
        waitForStableFrame(clear); clear.tap()
        XCTAssertFalse(app.buttons["generatePlans"].isEnabled)
        let scan = app.buttons["Scan Recent Chat"]
        for _ in 0..<5 where !scan.isHittable { app.swipeDown() }
        waitForStableFrame(scan); scan.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        let photos = app.images.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "PXGGridLayout-Info", "Photo, Screenshot"))
        guard photos.count >= 3 else {
            app.buttons["Cancel"].tap()
            throw XCTSkip("Seed the three exported demo screenshots into Simulator Photos first; see OCR/session TDD evidence.")
        }
        // Photos exposes these visible thumbnails as images rather than tappable controls.
        for index in [2, 1, 0] {
            photos.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        app.buttons["Done"].tap()
        let analyze = app.buttons["generatePlans"]
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Analyze 8 Messages"), object: analyze)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 20), .completed)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        waitForStableFrame(analyze); analyze.tap()
        XCTAssertTrue(app.staticTexts["Make it a group yes."].waitForExistence(timeout: 10))
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
