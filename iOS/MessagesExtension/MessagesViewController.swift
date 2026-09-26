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
        if !store.resumeAfterMaps(), let url = conversation.selectedMessage?.url { store.open(url) }
        requestPresentationStyle(.expanded)
    }
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        if let url = message.url { store.open(url) }
    }
    override func willResignActive(with conversation: MSConversation) {
        store.persistDemo()
        super.willResignActive(with: conversation)
    }
    private func insert(_ session: SideQuestSession, link: SessionLink) {
        guard let conversation = activeConversation else { store.status = "Open a conversation first."; return }
        do {
            let selected = conversation.selectedMessage
            let matching = selected?.url.flatMap { try? SessionLink.decode($0) }?.sessionId == session.id
            let message = MSMessage(session: (matching ? selected?.session : nil) ?? MSSession())
            let layout = MSMessageTemplateLayout()
            let title = "SIDEQUEST SET"
            let subtitle = session.winningPlan?.title ?? "Your next hangout"
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
                    summary = winner.title + "\n" + winner.start.formatted(.dateTime.weekday(.wide).hour().minute()) + "\n~$\(Int(winner.estimatedCostPerPerson))/person · 4 friends\nTap to open"
                } else { summary = "A little less planning.\nA lot more together." }
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
