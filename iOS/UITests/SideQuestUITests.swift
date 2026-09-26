import XCTest

final class SideQuestUITests: XCTestCase {
    func testContainingAppExplainsMessagesEntryPoint() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["You choose what SideQuest sees."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Find SideQuest in Messages"].exists)
    }
}
