import SwiftUI
import SideQuestCore

/// Search any place the group is considering and see whether it's listed as open at one of the group's times.
struct PlaceHoursCheckView: View {
    struct TimeOption: Identifiable, Hashable {
        let id: String
        let label: String
        let window: CalendarBusyInterval
        static func == (a: TimeOption, b: TimeOption) -> Bool { a.id == b.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }
    let options: [TimeOption]
    let center: ParticipantLocation?
    let area: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String
    @State private var results: [PlanVenue] = []
    @State private var searching = false
    @State private var message = ""

    init(options: [TimeOption], center: ParticipantLocation?, area: String) {
        self.options = options; self.center = center; self.area = area
        _selectedID = State(initialValue: options.first?.id ?? "")
    }
    private var selected: TimeOption? { options.first { $0.id == selectedID } ?? options.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                QuestSectionHeader(title: "Is it open?", subtitle: "Search a place your group is thinking about. SideQuest checks its listed hours for your time.",
                                   systemImage: "door.left.hand.open")
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Color.questSecondary).accessibilityHidden(true)
                    TextField("Place name, like a café or park", text: $query)
                        .submitLabel(.search).onSubmit(search).autocorrectionDisabled()
                        .accessibilityIdentifier("placeSearch")
                    if !query.isEmpty {
                        Button { query = ""; results = []; message = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.questSecondary) }
                            .accessibilityLabel("Clear search")
                    }
                }
                .padding(.horizontal, 16).frame(minHeight: 52)
                .background(Color.questSurface, in: Capsule()).overlay(Capsule().stroke(Color.questBorder))
                if options.count > 1 {
                    Picker("When", selection: $selectedID) { ForEach(options) { Text($0.label).tag($0.id) } }
                        .pickerStyle(.menu).tint(.questAccent)
                } else if let selected {
                    QuestPill(text: selected.label, systemImage: "clock.fill")
                }
                Button(action: search) { Label(searching ? "Checking hours…" : "Check hours", systemImage: "clock.badge.checkmark") }
                    .buttonStyle(QuestPrimaryButtonStyle())
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
                if searching { ProgressView().frame(maxWidth: .infinity) }
                if !message.isEmpty { Text(message).font(.subheadline).foregroundStyle(Color.questSecondary) }
                if let selected {
                    ForEach(results.indices, id: \.self) { index in
                        let venue = results[index]
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(venue.name).font(.system(.headline, design: .rounded))
                                    if let address = venue.address { Text(address).font(.caption).foregroundStyle(Color.questSecondary) }
                                }
                                Spacer(minLength: 8)
                                Button { venue.mapItem.openInMaps() } label: { Image(systemName: "map.fill") }
                                    .buttonStyle(QuestSecondaryButtonStyle()).accessibilityLabel("Open \(venue.name) in Apple Maps")
                            }
                            HoursBadge(status: venue.hoursStatus(from: selected.window.start, to: selected.window.end))
                            if let hours = venue.openingHours {
                                Text("Listed hours: " + hours).font(.caption2).foregroundStyle(Color.questSecondary)
                            }
                        }.questCard(padding: 16)
                    }
                }
                Text("Hours come from OpenStreetMap when a place lists them. Only the place's name and map position are looked up. Call ahead for holidays and events.")
                    .font(.caption).foregroundStyle(Color.questSecondary)
            }.padding(20)
        }
        .questScreen()
        .navigationTitle("Check a place").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true; message = ""
        Task { @MainActor in
            defer { searching = false }
            var venues = Array(await VenueResolver.searchMapKit(query: String(text.prefix(100)), center: center, area: area).prefix(5))
            guard !venues.isEmpty else { results = []; message = "No places found nearby. Try a more specific name."; return }
            let hours = await OpeningHoursDirectory.live(venues)
            for index in venues.indices where index < hours.count { venues[index].openingHours = hours[index] }
            results = venues
            if venues.allSatisfy({ $0.openingHours == nil }) { message = "These places don't list hours yet. Open one in Apple Maps to check." }
        }
    }
}
