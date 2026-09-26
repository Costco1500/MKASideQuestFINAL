import SwiftUI
import SideQuestCore

struct ProfileSetupView: View {
    @State var profile: Participant
    var saveTitle = "Save my context"
    var save: (Participant) -> Void
    @StateObject private var locationService = LocationService()
    @State private var manualLocation = false
    @State private var calendarStatus = ""
    @State private var loadingCalendar = false
    var body: some View {
        Form {
            Section("Only your own information") {
                TextField("Display name", text: $profile.displayName)
                Picker("Age range", selection: $profile.ageRange) {
                    ForEach(AgeRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Age is used only for activity eligibility.").font(.caption).foregroundStyle(Color.questSecondary)
            }.listRowBackground(Color.questSurface)
            Section("Your comfortable maximum") {
                Text("Up to \(profile.maxBudget, format: .currency(code: "USD")) per person")
                Slider(value: $profile.maxBudget, in: 0...80, step: 5).accessibilityLabel("Maximum budget")
                Text("The group stays within everyone's budget.").font(.caption)
            }.listRowBackground(Color.questSurface)
            Section("Location") {
                Button { locationService.requestLocation() } label: {
                    Label(locationService.fetching ? "Finding your area…" : "Use My Location", systemImage: "location.fill")
                }.buttonStyle(QuestPrimaryButtonStyle()).disabled(locationService.fetching).accessibilityIdentifier("useMyLocation")
                if profile.location != nil { Label("Near \(profile.approximateArea)", systemImage: "checkmark.circle.fill") }
                if !locationService.status.isEmpty && locationService.status != "Near \(profile.approximateArea)" { Text(locationService.status).font(.caption) }
                DisclosureGroup("Enter area manually", isExpanded: $manualLocation) {
                    TextField("Neighborhood, campus, or city area", text: $profile.approximateArea)
                        .onChange(of: profile.approximateArea) { _, _ in if manualLocation { profile.location = nil } }
                }
                Text("One-time location only. Your exact position stays on this device; the group receives a broad area.").font(.caption)
                #if DEBUG && targetEnvironment(simulator)
                Button("Use Atlanta demo location") { locationService.useDemoLocation() }.buttonStyle(QuestSecondaryButtonStyle())
                #endif
            }.listRowBackground(Color.questSurface)
            Section("When could you hang out?") {
                DatePicker("From", selection: $profile.availability.start)
                DatePicker("Until", selection: $profile.availability.end)
                Text("Choose at least 90 minutes, within a seven-day range.").font(.caption)
                Button(loadingCalendar ? "Reading availability…" : "Check my Apple Calendar") {
                    loadingCalendar = true
                    Task { @MainActor in
                        defer { loadingCalendar = false }
                        do {
                            let provider = EventKitCalendarProvider()
                            try await provider.requestAccess()
                            profile.busyIntervals = try await provider.busyIntervals(from: profile.availability.start, to: profile.availability.end)
                            profile.calendarConnectionStatus = "connected"
                            calendarStatus = "Availability loaded. Event titles stay on your device."
                        } catch { calendarStatus = error.localizedDescription }
                    }
                }.buttonStyle(QuestSecondaryButtonStyle()).disabled(loadingCalendar || profile.availability.duration <= 0)
                if !calendarStatus.isEmpty { Text(calendarStatus).font(.caption) }
                Text("Google calendars already in Apple's Calendar app are included.").font(.caption)
            }.listRowBackground(Color.questSurface)
            Button(saveTitle) { save(profile) }
                .buttonStyle(QuestPrimaryButtonStyle()).listRowBackground(Color.questSurface)
                .disabled(!profile.isValid).accessibilityIdentifier("saveProfile")
        }.scrollContentBackground(.hidden).questScreen().navigationTitle("Your context")
            .onChange(of: locationService.location) { _, found in
                guard let found else { return }
                manualLocation = false; profile.location = found
                profile.approximateArea = found.displayArea ?? "Your nearby area"
            }
            .onChange(of: profile.availability) { _, _ in
                profile.busyIntervals = []; profile.calendarConnectionStatus = "manual"; calendarStatus = "Time changed. Check your calendar again."
            }
    }
}
