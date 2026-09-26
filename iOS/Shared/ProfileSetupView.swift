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
    private enum RangeMode: Hashable { case week, custom }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Only your own information. Your group sees your name, budget, broad area, and free times. Never event titles or your exact location.")
                    .font(.subheadline).foregroundStyle(Color.questSecondary)
                aboutCard
                budgetCard
                locationCard
                timeCard
                Button(saveTitle) { save(profile) }
                    .buttonStyle(QuestPrimaryButtonStyle())
                    .disabled(!profile.isValid).accessibilityIdentifier("saveProfile")
                if let hint = validationHint { Text(hint).font(.caption).foregroundStyle(Color.questSecondary).frame(maxWidth: .infinity) }
            }.padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .questScreen().navigationTitle("Your context")
        .onAppear {
            // A saved "next 7 days" range goes stale; roll it forward so best times stay in the future.
            if profile.availability.isUpcomingWeek, profile.availability.start < Date().addingTimeInterval(-3600) { profile.availability = .upcomingWeek() }
        }
        .onChange(of: locationService.location) { _, found in
            guard let found else { return }
            manualLocation = false; profile.location = found
            profile.approximateArea = found.displayArea ?? "Your nearby area"
        }
        .onChange(of: profile.availability) { _, _ in
            if profile.calendarConnectionStatus == "connected" { calendarStatus = "Time changed. Check your calendar again." }
            profile.busyIntervals = []; profile.calendarConnectionStatus = "manual"
        }
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestSectionHeader(title: "About you", systemImage: "person.fill")
            TextField("Display name", text: $profile.displayName)
                .textContentType(.givenName).font(.system(.body, design: .rounded))
                .padding(.horizontal, 16).frame(minHeight: 50)
                .background(Color.questRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.questBorder))
            Picker("Age range", selection: $profile.ageRange) {
                ForEach(AgeRange.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented)
            Text("Age is used only for activity eligibility.").font(.caption).foregroundStyle(Color.questSecondary)
        }.questCard()
    }

    private var budgetCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestSectionHeader(title: "Your comfortable maximum", subtitle: "The group stays within everyone's budget.", systemImage: "dollarsign.circle.fill")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(profile.maxBudget == 0 ? "Free" : profile.maxBudget.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.system(size: 40, weight: .heavy, design: .rounded)).foregroundStyle(Color.questAccent)
                    .contentTransition(.numericText())
                Text(profile.maxBudget == 0 ? "only" : "per person, max").font(.subheadline).foregroundStyle(Color.questSecondary)
            }
            Slider(value: $profile.maxBudget, in: 0...80, step: 5).accessibilityLabel("Maximum budget")
            HStack { Text("Free"); Spacer(); Text("$80") }.font(.caption2).foregroundStyle(Color.questSecondary)
        }.questCard()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestSectionHeader(title: "Location", subtitle: "One-time only. Your exact position stays on this device; the group gets a broad area.",
                               systemImage: "location.fill")
            Button { locationService.requestLocation() } label: {
                Label(locationService.fetching ? "Finding your area…" : "Use My Location", systemImage: "location.fill")
            }.buttonStyle(QuestPrimaryButtonStyle()).disabled(locationService.fetching).accessibilityIdentifier("useMyLocation")
            if profile.location != nil {
                Label("Near \(profile.approximateArea)", systemImage: "checkmark.circle.fill").font(.subheadline.bold()).foregroundStyle(Color.questSuccess)
            }
            if !locationService.status.isEmpty && locationService.status != "Near \(profile.approximateArea)" {
                Text(locationService.status).font(.caption).foregroundStyle(Color.questSecondary)
            }
            DisclosureGroup("Enter area manually", isExpanded: $manualLocation) {
                TextField("Neighborhood, campus, or city area", text: $profile.approximateArea)
                    .padding(.horizontal, 14).frame(minHeight: 46)
                    .background(Color.questRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 8)
                    .onChange(of: profile.approximateArea) { _, _ in if manualLocation { profile.location = nil } }
            }.font(.system(.subheadline, design: .rounded, weight: .semibold))
            #if DEBUG && targetEnvironment(simulator)
            Button("Use Atlanta demo location") { locationService.useDemoLocation() }.buttonStyle(QuestSecondaryButtonStyle())
            #endif
        }.questCard()
    }

    private var rangeMode: Binding<RangeMode> {
        Binding(get: { profile.availability.isUpcomingWeek ? .week : .custom },
                set: { profile.availability = $0 == .week ? .upcomingWeek() : .nextEvening() })
    }

    private var timeCard: some View {
        let connected = profile.calendarConnectionStatus == "connected"
        let slots = AvailabilityEngine.bestTimes([profile], range: profile.availability, now: Date())
        return VStack(alignment: .leading, spacing: 14) {
            QuestSectionHeader(title: "When could you hang out?", subtitle: "SideQuest reads only busy times, never event titles.", systemImage: "calendar")
            Picker("Time range", selection: rangeMode) {
                Text("Next 7 days").tag(RangeMode.week)
                Text("Pick a window").tag(RangeMode.custom)
            }.pickerStyle(.segmented)
            if rangeMode.wrappedValue == .custom {
                DatePicker("From", selection: $profile.availability.start)
                DatePicker("Until", selection: $profile.availability.end)
                Text("Choose at least 90 minutes, within a seven-day range.").font(.caption).foregroundStyle(Color.questSecondary)
            } else {
                Text("\(profile.availability.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) through \(profile.availability.end.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))")
                    .font(.caption).foregroundStyle(Color.questSecondary)
            }
            Button(action: checkCalendar) {
                Label(loadingCalendar ? "Reading availability…" : (connected ? "Check my Apple Calendar again" : "Check my Apple Calendar"), systemImage: "calendar.badge.checkmark")
            }
            .buttonStyle(QuestSecondaryButtonStyle()).disabled(loadingCalendar || profile.availability.duration <= 0)
            .accessibilityIdentifier("checkCalendar")
            if !calendarStatus.isEmpty {
                Label(calendarStatus, systemImage: connected ? "checkmark.circle.fill" : "info.circle").font(.caption)
                    .foregroundStyle(connected ? Color.questSuccess : .questSecondary)
            }
            Divider().overlay(Color.questBorder)
            Text(connected ? "Your best times" : "Best times in your window").font(.system(.headline, design: .rounded, weight: .bold))
            if slots.isEmpty {
                Text("No 90-minute opening between 10 AM and 11 PM here. Try a wider window.").font(.subheadline).foregroundStyle(Color.questSecondary)
            }
            ForEach(slots.indices, id: \.self) { index in TimeSlotRow(slot: slots[index], isBest: index == 0) }
            Text(connected ? "Worked around your calendar. SideQuest picks the group's best overlap automatically."
                           : "Check your calendar so these skip your busy times. Google calendars already in Apple's Calendar app are included.")
                .font(.caption).foregroundStyle(Color.questSecondary)
        }.questCard()
    }

    private func checkCalendar() {
        loadingCalendar = true
        let range = profile.availability
        Task { @MainActor in
            defer { loadingCalendar = false }
            do {
                let provider = EventKitCalendarProvider()
                try await provider.requestAccess()
                let busy = try await provider.busyIntervals(from: range.start, to: range.end)
                guard profile.availability == range else { return }
                profile.busyIntervals = busy
                profile.calendarConnectionStatus = "connected"
                calendarStatus = busy.isEmpty ? "Calendar checked. You're wide open."
                    : "Calendar checked. Skipped \(busy.count) busy \(busy.count == 1 ? "block" : "blocks"); titles stay on your device."
            } catch { calendarStatus = error.localizedDescription }
        }
    }

    private var validationHint: String? {
        guard !profile.isValid else { return nil }
        if profile.displayName.trimmingCharacters(in: .whitespaces).isEmpty { return "Add your name to continue." }
        if profile.approximateArea.trimmingCharacters(in: .whitespaces).isEmpty { return "Share your location or enter your area to continue." }
        if profile.availability.duration < 5400 { return "Choose at least 90 minutes of availability." }
        return "Check your details to continue."
    }
}
