import XCTest

final class ShellTests: XCTestCase {
    func testContainingAppEmbedsMessagesExtension() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let bundle = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("SideQuestMessages.appex")))
        let configuration = try XCTUnwrap(bundle.infoDictionary?["NSExtension"] as? [String: Any])
        XCTAssertEqual(configuration["NSExtensionPointIdentifier"] as? String, "com.apple.message-payload-provider")
        XCTAssertEqual(configuration["NSExtensionMainStoryboard"] as? String, "MainInterface")
        XCTAssertNotNil(bundle.url(forResource: "MainInterface", withExtension: "storyboardc"))
    }
}
