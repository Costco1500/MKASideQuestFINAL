import SwiftUI

@main
struct SideQuestApp: App {
    @StateObject private var store = QuestStore()
    var body: some Scene { WindowGroup { QuestFlowView(store: store) } }
}
