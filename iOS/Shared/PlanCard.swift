import SwiftUI
import MapKit
import SideQuestCore

struct PlanCard<Footer: View>: View {
    let plan: PlanOption
    var onOpenMaps: (() -> Void)? = nil
    @ViewBuilder var footer: () -> Footer
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: PlanSymbol.name(for: plan)).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 50, height: 50).background(.questSunset, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.system(.title3, design: .rounded, weight: .bold))
                    Text(plan.activity).font(.subheadline).foregroundStyle(Color.questSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(plan.estimatedCostPerPerson == 0 ? "Free" : plan.estimatedCostPerPerson.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                    .font(.system(.headline, design: .rounded, weight: .bold)).foregroundStyle(Color.questAccent)
                    .padding(.horizontal, 10).padding(.vertical, 6).background(Color.questSoft, in: Capsule())
                    .accessibilityLabel(plan.estimatedCostPerPerson == 0 ? "Free" : "About \(Int(plan.estimatedCostPerPerson)) dollars per person")
            }
            if let second = plan.secondStop { Label("Then: \(second)", systemImage: "arrow.turn.down.right").font(.subheadline) }
            let window = CalendarBusyInterval(start: plan.start, end: plan.end)
            QuestPill(text: window.dayLabel + " · " + window.timeLabel, systemImage: "clock.fill")
            if let venue = plan.venue {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(venue.name, systemImage: "mappin.and.ellipse").font(.system(.headline, design: .rounded))
                        if let address = venue.address { Text(address).font(.caption).foregroundStyle(Color.questSecondary) }
                    }
                    Spacer(minLength: 4)
                    Button { onOpenMaps?(); venue.openInMaps() } label: { Image(systemName: "arrow.triangle.turn.up.right.diamond.fill") }
                        .buttonStyle(QuestSecondaryButtonStyle()).accessibilityLabel("Open \(venue.name) in Apple Maps").accessibilityIdentifier("openMaps-\(plan.id)")
                }
                Text("Real place · nothing booked yet").font(.caption2).foregroundStyle(Color.questSecondary)
            } else {
                Label(plan.area, systemImage: "mappin.and.ellipse").font(.headline)
                Text("Specific location not found").font(.caption).foregroundStyle(Color.questSecondary)
            }
            Text(plan.explanation).font(.subheadline).foregroundStyle(Color.questSecondary).fixedSize(horizontal: false, vertical: true)
            if !plan.concerns.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(plan.concerns, id: \.self) { Label($0, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Color.questSecondary) }
                    }.padding(.top, 6)
                } label: { Text("Good to know").font(.system(.subheadline, design: .rounded, weight: .semibold)) }
            }
            footer()
        }.questCard()
    }
}

extension PlanCard where Footer == EmptyView {
    init(plan: PlanOption, onOpenMaps: (() -> Void)? = nil) {
        self.init(plan: plan, onOpenMaps: onOpenMaps) { EmptyView() }
    }
}

enum PlanSymbol {
    static func name(for plan: PlanOption) -> String {
        let text = [plan.title, plan.activity, plan.venueSearchQuery ?? ""].joined(separator: " ").lowercased()
        let table: [([String], String)] = [
            (["clay", "pottery", "craft", "paint", "art supply"], "paintpalette.fill"),
            (["gallery", "museum", "exhibit"], "building.columns.fill"),
            (["park", "picnic", "hike", "trail", "garden", "outdoor"], "leaf.fill"),
            (["boba", "tea", "coffee", "cafe", "dessert", "ice cream"], "cup.and.saucer.fill"),
            (["movie", "film", "cinema"], "film.fill"),
            (["game", "bowling", "arcade", "trivia"], "gamecontroller.fill"),
            (["music", "concert", "karaoke"], "music.note"),
            (["photo", "camera"], "camera.fill"),
            (["sketch", "draw"], "pencil.and.scribble"),
            (["dinner", "lunch", "brunch", "food", "taco", "pizza", "restaurant", "ramen"], "fork.knife")
        ]
        return table.first { keywords, _ in keywords.contains { text.contains($0) } }?.1 ?? "sparkles"
    }
}
