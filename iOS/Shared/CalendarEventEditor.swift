import SwiftUI
import EventKit
import EventKitUI

struct CalendarEventEditor: UIViewControllerRepresentable {
    let title: String
    let start: Date
    let end: Date
    let area: String
    var completed: (Bool) -> Void

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        let store = EKEventStore()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        event.title = title; event.startDate = start; event.endDate = end
        event.location = area; event.notes = "Planned together with SideQuest."
        controller.event = event
        controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completed: completed) }
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let completed: (Bool) -> Void
        init(completed: @escaping (Bool) -> Void) { self.completed = completed }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
            completed(action == .saved)
        }
    }
}
