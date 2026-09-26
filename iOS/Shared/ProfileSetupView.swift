import SwiftUI
import SideQuestCore

struct ProfileSetupView: View {
    @State var profile: Participant
    var save: (Participant) -> Void
    @State private var calendarStatus = ""
    @State private var loadingCalendar = false
    var body: some View {
        Form {
            Section("Only your own information") {
                TextField("Display name", text: $profile.displayName)
                Picker("Age range", selection: $profile.ageRange) {
                    ForEach(AgeRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Age is used only for activity eligibility.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Your comfortable maximum") {
                Text("Up to \(profile.maxBudget, format: .currency(code: "USD")) per person")
                Slider(value: $profile.maxBudget, in: 0...80, step: 5).accessibilityLabel("Maximum budget")
                Text("The group stays within everyone's budget.").font(.caption)
            }
            Section("Approximate location") {
                TextField("Neighborhood, campus, or city area", text: $profile.approximateArea)
                Text("Enter an area manually. No home address or GPS required.").font(.caption)
            }
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
                }.disabled(loadingCalendar || profile.availability.duration <= 0)
                if !calendarStatus.isEmpty { Text(calendarStatus).font(.caption) }
                Text("Google calendars already in Apple's Calendar app are included.").font(.caption)
            }
            Button("Save my context") { save(profile) }
                .disabled(!profile.isValid).accessibilityIdentifier("saveProfile")
        }.navigationTitle("Your context")
            .onChange(of: profile.availability) { _, _ in
                profile.busyIntervals = []; profile.calendarConnectionStatus = "manual"; calendarStatus = "Time changed. Check your calendar again."
            }
    }
}
