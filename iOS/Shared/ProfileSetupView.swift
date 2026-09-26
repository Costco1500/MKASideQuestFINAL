import SwiftUI
import SideQuestCore

struct ProfileSetupView: View {
    @State var profile: Participant
    var save: (Participant) -> Void
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
            }
            Button("Save my context") { save(profile) }
                .disabled(!profile.isValid).accessibilityIdentifier("saveProfile")
        }.navigationTitle("Your context")
    }
}
