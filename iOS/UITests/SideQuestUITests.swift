import XCTest

final class SideQuestUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }
    override func tearDown() {
        if (testRun?.failureCount ?? 0) > 0 {
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
            for bundle in ["com.sidequest.app", "com.apple.MobileSMS", "com.apple.mobileslideshow"] {
                let app = XCUIApplication(bundleIdentifier: bundle)
                if app.state == .runningForeground { print("FAILURE UI: \(app.debugDescription)") }
            }
        }
    }
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
        XCTAssertTrue(app.staticTexts["Make it a group yes."].waitForExistence(timeout: 60))
        let vote = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@", "vote-", "-down")).firstMatch
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
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 60))
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
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: messages.buttons["Choose Messages"])
        XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 8), .completed)
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
        if resetSession, messages.buttons["New"].waitForExistence(timeout: 5) {
            waitForStableFrame(messages.buttons["New"]); messages.buttons["New"].tap()
        }
        return messages
    }
    func testMessagesWinnerOffersCalendarAndShare() {
        let messages = openMessagesExtension()
        waitForStableFrame(messages.buttons["Try Demo"]); messages.buttons["Try Demo"].tap()
        readDemoChat(in: messages)
        waitForStableFrame(messages.buttons["generatePlans"]); messages.buttons["generatePlans"].tap()
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 60))
        let groundedPlan = messages.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "openMaps-")).firstMatch
        XCTAssertTrue(groundedPlan.waitForExistence(timeout: 8), "At least one live demo search should resolve a venue")
        let planID = String(groundedPlan.identifier.dropFirst("openMaps-".count))
        let vote = messages.buttons["vote-\(planID)-down"]
        for _ in 0..<5 where !vote.isHittable { messages.swipeUp() }
        waitForStableFrame(vote); vote.tap()
        let finalize = messages.buttons["finalize"]
        for _ in 0..<8 where !finalize.isHittable { messages.swipeUp() }
        waitForStableFrame(finalize); finalize.tap()
        let openMaps = messages.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "openMaps-")).firstMatch
        XCTAssertTrue(openMaps.waitForExistence(timeout: 8), "Live MapKit should ground the winning demo plan")
        for _ in 0..<5 where !openMaps.isHittable { messages.swipeDown() }
        waitForStableFrame(openMaps); openMaps.tap()
        let maps = XCUIApplication(bundleIdentifier: "com.apple.Maps")
        XCTAssertTrue(maps.wait(for: .runningForeground, timeout: 10))
        if maps.buttons["Continue"].waitForExistence(timeout: 2) { maps.buttons["Continue"].tap() }
        let mapsPermission = XCUIApplication(bundleIdentifier: "com.apple.springboard").buttons["Allow While Using App"]
        if mapsPermission.waitForExistence(timeout: 2) { mapsPermission.tap() }
        let mapAttachment = XCTAttachment(screenshot: maps.screenshot()); mapAttachment.lifetime = .keepAlways; add(mapAttachment)
        messages.activate()
        XCTAssertTrue(messages.wait(for: .runningForeground, timeout: 10))
        if messages.buttons["add"].exists {
            waitForStableFrame(messages.buttons["add"])
            messages.buttons["add"].tap()
            let sidequest = messages.staticTexts["SideQuest"].firstMatch
            for _ in 0..<3 where !sidequest.exists { messages.swipeUp() }
            XCTAssertTrue(sidequest.waitForExistence(timeout: 5)); sidequest.tap()
        }
        let calendar = messages.buttons["Add to Calendar"]
        reveal(calendar, in: messages)
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
        let loaded = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Analyze Recent Chat"), object: analyze)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 15), .completed)
    }
    func testScreenshotReviewSelectionAndSenderCorrection() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Try Demo"].tap()
        readDemoChat(in: app)
        app.buttons["Choose Messages"].tap()
        let clear = app.buttons["Clear"]
        reveal(clear, in: app)
        waitForStableFrame(clear); clear.tap()
        XCTAssertFalse(app.buttons["generatePlans"].isEnabled)
        let latest = app.buttons["Last 10"]
        reveal(latest, in: app)
        waitForStableFrame(latest); latest.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["generatePlans"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        let sender = app.buttons.matching(identifier: "messageSender").firstMatch
        reveal(sender, in: app)
        waitForStableFrame(sender); sender.tap()
        let unknown = app.buttons["Unknown"].firstMatch
        XCTAssertTrue(unknown.waitForExistence(timeout: 5)); unknown.tap()
        XCTAssertEqual(sender.label, "Unknown")
        let scan = app.buttons["Scan Recent Chat"]
        reveal(scan, in: app)
        waitForStableFrame(scan); scan.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 10))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["generatePlans"].isEnabled, "Cancel retains the reviewed selection")
    }
    func testPhotosPickerImportsScreenshots() throws {
        let app = openMessagesExtension()
        waitForStableFrame(app.buttons["Try Demo"]); app.buttons["Try Demo"].tap()
        readDemoChat(in: app)
        app.buttons["Choose Messages"].tap()
        let clear = app.buttons["Clear"]
        reveal(clear, in: app)
        waitForStableFrame(clear); clear.tap()
        XCTAssertFalse(app.buttons["generatePlans"].isEnabled)
        let scan = app.buttons["Scan Recent Chat"]
        reveal(scan, in: app)
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
        XCTAssertTrue(app.staticTexts["Make it a group yes."].waitForExistence(timeout: 60))
    }
    func testOneTimeLocationAndManualArea() {
        let app = XCUIApplication(); app.launch()
        app.buttons["Set up my profile"].tap()
        app.buttons["Use My Location"].tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow While Using App"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
        let area = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Near ")).firstMatch
        XCTAssertTrue(area.waitForExistence(timeout: 25), "Set a simulated location before running this integration test")
        XCTAssertFalse(app.staticTexts["Demo · Near Midtown Atlanta"].exists)
        app.buttons["Enter area manually"].tap()
        XCTAssertTrue(app.textFields["Neighborhood, campus, or city area"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
    }
    func testShareExtensionImportsIntoMessages() throws {
        XCUIApplication(bundleIdentifier: "com.apple.MobileSMS").terminate()
        let photos = XCUIApplication(bundleIdentifier: "com.apple.mobileslideshow"); photos.launch()
        if photos.buttons["Done"].exists { photos.buttons["Done"].tap() }
        if photos.buttons["Close"].exists { photos.buttons["Close"].tap() }
        if photos.buttons["Continue"].waitForExistence(timeout: 3) { photos.buttons["Continue"].tap() }
        if photos.buttons["Cancel"].exists { photos.buttons["Cancel"].tap() }
        let screenshots = photos.images.matching(NSPredicate(format: "identifier == %@ AND label BEGINSWITH %@", "PXGGridLayout-Info", "Photo, Screenshot"))
        guard screenshots.count >= 3 else { throw XCTSkip("Seed the three demo screenshots into Simulator Photos first.") }
        photos.buttons["Select"].tap()
        for index in [2, 1, 0] {
            screenshots.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(photos.buttons["Share"].isEnabled)
        photos.buttons["Share"].tap()
        let sidequest = photos.cells["SideQuest"]
        XCTAssertTrue(sidequest.waitForExistence(timeout: 5)); sidequest.tap()
        let found = photos.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " messages found")).firstMatch
        XCTAssertTrue(found.waitForExistence(timeout: 25))
        let count = try XCTUnwrap(Int(found.label.components(separatedBy: " ")[0]))
        XCTAssertGreaterThanOrEqual(count, 8) // Photos may deliver overlapping screenshots in library order.
        XCTAssertTrue(photos.staticTexts["Ready for SideQuest"].exists)
        let attachment = XCTAttachment(screenshot: photos.screenshot()); attachment.lifetime = .keepAlways; add(attachment)
        photos.buttons["Done"].tap()
        let messages = openMessagesExtension(resetSession: false)
        XCTAssertTrue(messages.staticTexts["Conversation ready"].waitForExistence(timeout: 10))
        XCTAssertTrue(messages.staticTexts["\(count) messages imported"].exists)
        messages.buttons["Review Messages"].tap()
        XCTAssertFalse(messages.staticTexts["Conversation ready"].exists)
        let demo = messages.buttons["Try Demo"]
        if demo.exists { waitForStableFrame(demo); demo.tap() }
        let analyze = messages.buttons["generatePlans"]
        let imported = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@ AND enabled == true", "Analyze 8 Messages"), object: analyze)
        XCTAssertEqual(XCTWaiter.wait(for: [imported], timeout: 10), .completed)
        waitForStableFrame(analyze); analyze.tap()
        XCTAssertTrue(messages.staticTexts["Make it a group yes."].waitForExistence(timeout: 60))
    }
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews["questScroll"]
        for _ in 0..<12 {
            let frame = element.frame
            if element.isHittable && frame.minY >= 155 && frame.maxY < app.frame.maxY - 150 { return }
            let up = frame.maxY >= app.frame.maxY - 150
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.6 : 0.35))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.35 : 0.6))
            start.press(forDuration: 0.1, thenDragTo: end)
        }
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
