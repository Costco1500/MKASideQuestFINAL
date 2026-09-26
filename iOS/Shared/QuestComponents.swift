import SwiftUI
import SideQuestCore

/// Sunset headline card for the moments that matter: start, invite, and the final pick.
struct QuestHero<Accessory: View>: View {
    let title: String
    let subtitle: String
    var symbol = "sun.horizon.fill"
    @ViewBuilder var accessory: () -> Accessory
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 30, weight: .semibold)).foregroundStyle(.white.opacity(0.95))
                .accessibilityHidden(true)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .heavy)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.system(.headline, design: .rounded, weight: .medium)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            accessory()
        }
        .padding(24).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.questSunset)
                Circle().fill(.white.opacity(0.14)).frame(width: 150).offset(x: 50, y: -60)
                Circle().fill(.white.opacity(0.08)).frame(width: 90).offset(x: -30, y: 70)
            }.clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .shadow(color: Color(uiColor: QuestPalette.sunset[2]).opacity(0.25), radius: 22, y: 12)
    }
}

extension QuestHero where Accessory == EmptyView {
    init(title: String, subtitle: String, symbol: String = "sun.horizon.fill") {
        self.init(title: title, subtitle: subtitle, symbol: symbol) { EmptyView() }
    }
}

struct QuestSectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage).font(.system(.body, weight: .semibold)).foregroundStyle(Color.questAccent)
                .frame(width: 36, height: 36).background(Color.questSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded, weight: .bold))
                if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Color.questSecondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

struct QuestPill: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color = .questText
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text)
        }
        .font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.questSoft.opacity(0.7), in: Capsule())
    }
}

/// Dismissible message strip; keeps the `status` identifier the UI tests read.
struct QuestStatusBanner: View {
    let text: String
    var dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill").foregroundStyle(Color.questAccent).accessibilityHidden(true)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("status")
            Button { dismiss() } label: { Image(systemName: "xmark").font(.caption.bold()).foregroundStyle(Color.questSecondary) }
                .frame(width: 32, height: 32).accessibilityLabel("Dismiss message")
        }
        .padding(14).background(Color.questRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.questClay.opacity(0.35)))
    }
}

struct ParticipantAvatar: View {
    let name: String
    var ready: Bool? = nil
    var size: CGFloat = 40
    private static let tints: [Color] = [.questClay, .questAmber, .questSuccess, .questAccent]
    var body: some View {
        let initial = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        let tint = Self.tints[abs(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % Self.tints.count]
        Text(initial).font(.system(size: size * 0.42, weight: .bold, design: .rounded)).foregroundStyle(Color.questText)
            .frame(width: size, height: size)
            .background(tint.opacity(0.28), in: Circle())
            .overlay(Circle().stroke(Color.questSurface, lineWidth: 2))
            .overlay(alignment: .bottomTrailing) {
                if let ready {
                    Image(systemName: ready ? "checkmark.circle.fill" : "clock.fill")
                        .font(.system(size: size * 0.34)).foregroundStyle(ready ? Color.questSuccess : .questSecondary)
                        .background(Color.questSurface, in: Circle()).offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}

/// Ring showing how many people have tapped Done.
struct ReadinessRing: View {
    let ready: Int
    let expected: Int
    var body: some View {
        let progress = expected == 0 ? 0 : Double(ready) / Double(expected)
        ZStack {
            Circle().stroke(Color.questSoft, lineWidth: 8)
            Circle().trim(from: 0, to: progress).stroke(.questPrimary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(ready)/\(expected)").font(.system(.headline, design: .rounded, weight: .bold))
                Text("Done").font(.caption2).foregroundStyle(Color.questSecondary)
            }
        }.frame(width: 72, height: 72).accessibilityHidden(true)
    }
}

/// Invite → Share → Plan → Vote → Go.
struct QuestStepProgress: View {
    let current: Int
    private let steps = ["Chat", "Understand", "Vote", "Go"]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                VStack(spacing: 6) {
                    Capsule().fill(index <= current ? AnyShapeStyle(.questPrimary) : AnyShapeStyle(Color.questSoft)).frame(height: 6)
                    Text(steps[index]).font(.system(.caption2, design: .rounded, weight: index == current ? .bold : .medium))
                        .foregroundStyle(index == current ? Color.questText : .questSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(steps.count): \(steps[min(current, steps.count - 1)])")
    }
}

extension CalendarBusyInterval {
    /// "Fri, Oct 2" / "Today" / "Tomorrow".
    var dayLabel: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(start) { return "Today" }
        if calendar.isDateInTomorrow(start) { return "Tomorrow" }
        return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
    var timeLabel: String { start.formatted(date: .omitted, time: .shortened) + " – " + end.formatted(date: .omitted, time: .shortened) }
}

struct TimeSlotRow: View {
    let slot: RankedTimeSlot
    let isBest: Bool
    var body: some View {
        HStack(spacing: 14) {
            VStack(spacing: 0) {
                Text(slot.window.start.formatted(.dateTime.weekday(.abbreviated)).uppercased()).font(.system(.caption2, design: .rounded, weight: .bold))
                    .foregroundStyle(isBest ? Color(uiColor: QuestPalette.primaryText) : .questAccent)
                Text(slot.window.start.formatted(.dateTime.day())).font(.system(.title3, design: .rounded, weight: .heavy))
                    .foregroundStyle(isBest ? Color(uiColor: QuestPalette.primaryText) : .questText)
            }
            .frame(width: 52, height: 56)
            .background(isBest ? AnyShapeStyle(.questPrimary) : AnyShapeStyle(Color.questSoft), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(slot.window.timeLabel).font(.system(.headline, design: .rounded))
                    if isBest { QuestPill(text: "Best", systemImage: "star.fill", tint: .questAccent) }
                }
                Text(slot.window.dayLabel + " · " + slot.reasons.joined(separator: " · ")).font(.caption).foregroundStyle(Color.questSecondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Ranked list of meet-up times with a reason line for each.
struct BestTimesCard: View {
    let title: String
    let subtitle: String
    let slots: [RankedTimeSlot]
    var emptyMessage = "No shared 90-minute window yet. Edit availability before planning."
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            QuestSectionHeader(title: title, subtitle: subtitle, systemImage: "calendar.badge.clock")
            if slots.isEmpty { Text(emptyMessage).font(.subheadline).foregroundStyle(Color.questSecondary) }
            ForEach(slots.indices, id: \.self) { index in
                TimeSlotRow(slot: slots[index], isBest: index == 0)
                if index < slots.count - 1 { Divider().overlay(Color.questBorder) }
            }
        }.questCard()
    }
}

/// Whether the venue is listed as open for the whole plan.
struct HoursBadge: View {
    let status: VenueHoursStatus
    var compact = false
    var body: some View {
        Label { Text(text).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: icon) }
            .font(.system(compact ? .caption : .subheadline, design: .rounded, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
    var text: String {
        switch status {
        case .open(_, true): return "Open 24 hours"
        case .open(let until, false): return "Open then · until \(time(until))"
        case .closesEarly(let at): return "Closes at \(time(at)), before you're done"
        case .opensLate(let at): return "Opens at \(time(at)), start a little later"
        case .closed: return "Closed at that time"
        case .unknown: return "Hours not listed · check before you go"
        }
    }
    private var icon: String {
        switch status {
        case .open: return "checkmark.seal.fill"
        case .closesEarly: return "clock.badge.exclamationmark"
        case .opensLate: return "clock.arrow.circlepath"
        case .closed: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }
    private var tint: Color {
        switch status {
        case .open: return .questSuccess
        case .closesEarly, .opensLate: return .questWarning
        case .closed: return .questDestructive
        case .unknown: return .questSecondary
        }
    }
}

/// Down / Maybe / Pass with the existing identifiers.
struct VoteButtons: View {
    let plan: PlanOption
    let selected: VoteValue?
    var disabled = false
    var vote: (VoteValue) -> Void
    var body: some View {
        HStack(spacing: 8) {
            ForEach(VoteValue.allCases, id: \.self) { value in
                let isSelected = selected == value
                Button { vote(value) } label: {
                    Label(value.label, systemImage: icon(value)).font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .foregroundStyle(isSelected ? Color(uiColor: QuestPalette.primaryText) : .questText)
                        .background(isSelected ? tint(value) : .questRaised, in: Capsule())
                        .overlay(Capsule().stroke(isSelected ? .clear : Color.questBorder))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("vote-\(plan.id)-\(value.rawValue)")
                .accessibilityLabel(value.label)
                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                .disabled(disabled)
            }
        }
    }
    private func icon(_ value: VoteValue) -> String {
        switch value { case .down: return "hand.thumbsup.fill"; case .maybe: return "hand.raised.fill"; case .pass: return "hand.thumbsdown.fill" }
    }
    private func tint(_ value: VoteValue) -> Color {
        switch value { case .down: return .questSuccess; case .maybe: return .questWarning; case .pass: return .questSecondary }
    }
}

/// Shown when a shared session needs a server this phone can reach.
struct ServerSetupCard: View {
    var openSettings: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QuestSectionHeader(title: "Connect your group's server",
                               subtitle: "Group chats share one SideQuest server so everyone sees the same plan. Add its HTTPS address in Settings.",
                               systemImage: "antenna.radiowaves.left.and.right")
            Button { openSettings() } label: { Label("Open Settings", systemImage: "gearshape.fill") }
                .buttonStyle(QuestSecondaryButtonStyle())
        }.questCard()
    }
}
