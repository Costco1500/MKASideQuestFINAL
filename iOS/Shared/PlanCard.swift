import SwiftUI
import SideQuestCore

struct PlanCard: View {
    let plan: PlanOption
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(plan.title).font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Text(plan.estimatedCostPerPerson, format: .currency(code: "USD")).font(.headline).foregroundStyle(Color.questAccent)
            }
            Text(plan.activity)
            if let second = plan.secondStop { Text("Then: \(second)") }
            Label(plan.start.formatted(date: .abbreviated, time: .shortened) + " – " + plan.end.formatted(date: .omitted, time: .shortened), systemImage: "clock")
            Label(plan.area, systemImage: "mappin.and.ellipse")
            Text(plan.explanation).font(.subheadline).foregroundStyle(.secondary)
            ForEach(plan.concerns, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }.questCard()
    }
}
