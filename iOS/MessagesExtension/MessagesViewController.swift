import Messages
import SwiftUI
import SideQuestCore

final class MessagesViewController: MSMessagesAppViewController {
    private let store = QuestStore()
    override func viewDidLoad() {
        super.viewDidLoad()
        store.expand = { [weak self] in self?.requestPresentationStyle(.expanded) }
        store.insert = { [weak self] session, link in self?.insert(session, link: link) }
        let host = UIHostingController(rootView: QuestFlowView(store: store))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
    }

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        store.chatSize = conversation.remoteParticipantIdentifiers.count + 1
        if let url = conversation.selectedMessage?.url { store.open(url) }
        else { store.resumeAfterMaps() }
        store.checkPendingImport()
        if DemoConfiguration.preloadConversation, store.session == nil, store.invitation == nil,
           store.pendingImportCount == 0, store.messages.isEmpty { store.startDemo() }
    }
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        if let url = message.url { store.open(url) }
    }
    override func willResignActive(with conversation: MSConversation) {
        store.stopReading(); store.messages = []
        super.willResignActive(with: conversation)
    }
    private func insert(_ session: SideQuestSession, link: SessionLink) {
        guard let conversation = activeConversation else { store.status = "Open a conversation first."; return }
        do {
            let selected = conversation.selectedMessage
            let matching = selected?.url.flatMap { try? SessionLink.decode($0) }?.sessionId == session.id
            let message = MSMessage(session: (matching ? selected?.session : nil) ?? MSSession())
            let layout = MSMessageTemplateLayout()
            let title = session.winningPlan != nil ? "SIDEQUEST SET 🎉" : (session.planOptions.isEmpty ? "Join our SideQuest" : "3 plans ready")
            let subtitle = session.winningPlan?.title ?? (session.planOptions.isEmpty ? "Add your context to plan together" : "Tap to vote · Down / Maybe / Pass")
            layout.caption = title; layout.subcaption = subtitle
            layout.image = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 300)).image { context in
                let canvas = context.cgContext
                if let sunset = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: QuestPalette.sunset.map(\.cgColor) as CFArray, locations: [0, 0.55, 1]) {
                    canvas.drawLinearGradient(sunset, start: .zero, end: CGPoint(x: 600, y: 300), options: [])
                }
                UIColor.white.withAlphaComponent(0.13).setFill()
                canvas.fillEllipse(in: CGRect(x: 440, y: -110, width: 280, height: 280))
                UIColor.white.withAlphaComponent(0.07).setFill()
                canvas.fillEllipse(in: CGRect(x: -60, y: 210, width: 180, height: 180))
                // Messages overlays the app icon on the top-left corner, so the wordmark starts after it.
                ("✦ SIDEQUEST" as NSString).draw(at: CGPoint(x: 100, y: 28), withAttributes: [.font: UIFont.systemFont(ofSize: 24, weight: .heavy), .foregroundColor: UIColor.white])
                let summary: String
                if let winner = session.winningPlan {
                    let hours = winner.venue.map { HoursBadge(status: $0.hoursStatus(from: winner.start, to: winner.end)).text }
                    summary = winner.title + "\n" + winner.start.formatted(date: .abbreviated, time: .shortened) + " – " + winner.end.formatted(date: .omitted, time: .shortened) + "\n" + (winner.venue?.name ?? winner.area) + "\n" + (hours ?? "~$\(Int(winner.estimatedCostPerPerson))/person · \(session.participants.count) people")
                } else if session.planOptions.isEmpty { summary = "Good plans start\nwith everyone's input.\nTap to join." }
                else { summary = session.planOptions.enumerated().map { "\($0.offset + 1). \($0.element.title)" }.joined(separator: "\n") }
                (summary as NSString).draw(in: CGRect(x: 30, y: 92, width: 540, height: 196), withAttributes: [.font: UIFont.systemFont(ofSize: 25, weight: .bold), .foregroundColor: UIColor.white])
            }
            message.layout = layout; message.url = try link.url(); message.summaryText = "SideQuest: " + subtitle
            conversation.insert(message) { [weak self] error in
                Task { @MainActor in self?.store.status = error == nil ? "Card inserted. Tap Send when you're ready." : "Could not insert the card. Try again." }
            }
            requestPresentationStyle(.compact)
        } catch { store.status = error.localizedDescription }
    }
}
