import XCTest

final class SideQuestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            capture("Failure")
            for bundle in ["com.sidequest.app", "com.apple.MobileSMS", "com.apple.Maps"] {
                let app = XCUIApplication(bundleIdentifier: bundle)
                if app.state == .runningForeground { print(app.debugDescription) }
            }
        }
    }
    func testOfflineAppWalkthroughAndReset() {
        let app = XCUIApplication(); app.launch()
        checkConversation(app)
        app.buttons["About this prototype"].tap()
        XCTAssertTrue(app.staticTexts["This walkthrough uses a fictional conversation, curated plans, and simulated friends' votes. No live AI analysis takes place."].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        reachWinner(app, inspectContext: true)
        app.buttons["Add to Calendar"].tap()
        let cancel = app.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        capture("App Calendar")
        cancel.tap()
        if app.buttons["Discard Changes"].waitForExistence(timeout: 1) { app.buttons["Discard Changes"].tap() }
        XCTAssertTrue(app.buttons["Share Final Plan"].waitForExistence(timeout: 5))
        app.buttons["Demo options"].tap()
        app.buttons["Reset Demo"].tap()
        checkConversation(app)
    }
    func testMessagesMapsCalendarAndFinalCard() {
        let messages = openMessages()
        messages.buttons["Demo options"].tap()
        messages.buttons["Reset Demo"].tap()
        checkConversation(messages)
        reachWinner(messages)
        let mapsButton = messages.buttons["openMaps-plan-1"]
        reveal(mapsButton, in: messages); stable(mapsButton); mapsButton.tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 8))
        capture("Native Apple Maps")
        messages.activate()
        XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 8))
        if messages.buttons["add"].exists { openDrawer(messages) }
        let grabber = messages.buttons["Sheet Grabber"]
        if grabber.waitForExistence(timeout: 3), grabber.value as? String == "Half screen" {
            grabber.tap(); stable(messages.scrollViews["questScroll"])
        }
        let calendar = messages.buttons["Add to Calendar"]
        XCTAssertTrue(calendar.waitForExistence(timeout: 5))
        stable(calendar); calendar.tap()
        let cancel = messages.buttons["Cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 8))
        capture("Native Calendar")
        cancel.tap()
        if messages.buttons["Discard Changes"].waitForExistence(timeout: 1) { messages.buttons["Discard Changes"].tap() }
        let share = messages.buttons["Share Final Plan"]
        stable(share); share.tap()
        XCTAssertTrue(messages.buttons["Send"].waitForExistence(timeout: 8))
        capture("Final plan draft")
        messages.buttons["Remove app from message"].tap()
    }
    private func checkConversation(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["Recent group chat"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["Analyze Recent Chat"].isEnabled)
        for label in ["Start SideQuest", "Try Demo", "Settings", "Scan Recent Chat", "Review Messages", "Join SideQuest"] {
            XCTAssertFalse(app.buttons[label].exists, label)
        }
        capture("Conversation")
    }
    private func reachWinner(_ app: XCUIApplication, inspectContext: Bool = false) {
        app.buttons["Analyze Recent Chat"].tap()
        XCTAssertTrue(app.staticTexts["What the group wants"].waitForExistence(timeout: 5))
        capture("Group understanding")
        if inspectContext {
            let group = app.buttons.containing(.staticText, identifier: "Meet the group").firstMatch
            if group.exists { reveal(group, in: app); group.tap() }
        }
        app.buttons["Show 3 plans"].tap()
        XCTAssertTrue(app.staticTexts["SideQuest found 3 plans"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Simulate group votes"].isEnabled)
        let why = app.buttons["why-plan-1"]
        reveal(why, in: app); stable(why); why.tap()
        XCTAssertTrue(app.staticTexts["You wanted pottery — start with an easy air-dry clay craft."].exists)
        capture("Why it works")
        why.tap()
        let vote = app.buttons["vote-plan-1-down"]
        reveal(vote, in: app); stable(vote); vote.tap()
        XCTAssertEqual(vote.value as? String, "Selected")
        app.buttons["Simulate group votes"].tap()
        XCTAssertTrue(app.staticTexts["SideQuest set!"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Clay & Boba"].firstMatch.exists)
        capture("Winner")
    }
    @discardableResult private func openMessages() -> XCUIApplication {
        let messages = XCUIApplication(bundleIdentifier: "com.apple.MobileSMS"); messages.launch()
        if !messages.buttons["add"].exists, messages.cells.firstMatch.waitForExistence(timeout: 8) { messages.cells.firstMatch.tap() }
        openDrawer(messages)
        XCTAssertTrue(messages.buttons["Demo options"].waitForExistence(timeout: 8))
        return messages
    }
    private func openDrawer(_ messages: XCUIApplication) {
        let add = messages.buttons["add"]
        stable(add); add.tap()
        let photos = messages.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photos")).firstMatch
        XCTAssertTrue(photos.waitForExistence(timeout: 5))
        let quest = messages.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "SideQuest")).firstMatch
        for _ in 0..<4 where !quest.waitForExistence(timeout: 1) { messages.swipeUp() }
        XCTAssertTrue(quest.waitForExistence(timeout: 5)); quest.tap()
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["questScroll"]
        for _ in 0..<8 {
            let frame = element.frame
            if element.isHittable && frame.minY >= 155 && frame.maxY < app.frame.maxY - 155 { return }
            if frame.minY < 155 { scroll.swipeDown(velocity: .slow) }
            else { scroll.swipeUp(velocity: .slow) }
        }
    }
    private func stable(_ element: XCUIElement) {
        var previous = CGRect.null
        var count = 0
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists else { return false }
            let frame = element.frame
            count = element.isHittable && frame == previous ? count + 1 : 0
            previous = frame
            return count >= 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
