import XCTest
@testable import SideQuestCore
@testable import SideQuest

final class SharedImportTests: XCTestCase {
    func testRoundTripPendingImportAndClear() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SharedImportStore(directory: directory)
        XCTAssertFalse(store.hasPendingImport)
        let messages = DemoData.chatScript(nil)
        try store.saveImportedMessages(messages)
        XCTAssertTrue(store.hasPendingImport)
        XCTAssertEqual(try store.loadImportedMessages(), messages)
        try store.clearImportedMessages()
        XCTAssertFalse(store.hasPendingImport)
        XCTAssertEqual(try store.loadImportedMessages(), [])
    }
    @MainActor func testReviewConsumesDraftButPreservesImportDuringExistingPoll() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let handoff = SharedImportStore(directory: directory)
        let messages = DemoData.chatScript(nil)
        try handoff.saveImportedMessages(messages)
        let store = QuestStore(useLiveServices: false)
        store.startDemo()
        store.reviewPendingImport(from: handoff)
        XCTAssertEqual(store.messages, messages)
        XCTAssertFalse(store.isPreloadedConversation)
        XCTAssertFalse(handoff.hasPendingImport)

        try handoff.saveImportedMessages(messages)
        store.session = try SideQuestSession.demo()
        store.messages = []
        store.reviewPendingImport(from: handoff)
        XCTAssertTrue(handoff.hasPendingImport, "A current poll must not swallow a new import")
        XCTAssertTrue(store.messages.isEmpty)
    }
    func testUnavailableAppGroupFailsRatherThanUsingPrivateDefaults() {
        let store = SharedImportStore(directory: nil)
        XCTAssertThrowsError(try store.saveImportedMessages(DemoData.chatScript(nil)))
        XCTAssertFalse(store.hasPendingImport)
    }
    func testShareTargetIsEmbeddedWithImageOnlyActivationAndSameGroup() throws {
        let extensionURL = try XCTUnwrap(Bundle.main.builtInPlugInsURL).appendingPathComponent("SideQuestShare.appex")
        let bundle = try XCTUnwrap(Bundle(url: extensionURL))
        let info = try XCTUnwrap(bundle.infoDictionary?["NSExtension"] as? [String: Any])
        XCTAssertEqual(info["NSExtensionPointIdentifier"] as? String, "com.apple.share-services")
        let attributes = try XCTUnwrap(info["NSExtensionAttributes"] as? [String: Any])
        let rules = try XCTUnwrap(attributes["NSExtensionActivationRule"] as? [String: Any])
        XCTAssertEqual(rules["NSExtensionActivationSupportsImageWithMaxCount"] as? Int, 10)
        XCTAssertNil(rules["NSExtensionActivationSupportsText"])
    }
}
