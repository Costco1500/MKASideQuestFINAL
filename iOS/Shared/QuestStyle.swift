import SwiftUI

/// All SideQuest colors adapt independently to warm light and dark appearances.
enum QuestPalette {
    private static func rgb(_ hex: UInt) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt, _ dark: UInt) -> UIColor {
        UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) }
    }
    static let background = adaptive(0xF6F0E7, 0x1B1714)
    static let surface = adaptive(0xFDFBF7, 0x27211D)
    static let raised = adaptive(0xFFF8EF, 0x332A24)
    static let clay = adaptive(0xC97854, 0xD98A64)
    static let amber = adaptive(0xD79A5B, 0xE0A563)
    static let soft = adaptive(0xE9B87E, 0x63472F)
    static let text = adaptive(0x2C2520, 0xF3E9DD)
    static let secondary = adaptive(0x74675E, 0xB9AA9D)
    static let border = adaptive(0xE8DDD1, 0x43382F)
    static let success = adaptive(0x526B42, 0xA5BC91)
    static let link = adaptive(0x964D30, 0xE9B87E)
    // Deeper clay keeps cream button labels readable at normal text sizes.
    static let primaryFill = adaptive(0x995033, 0xD98A64)
    static let primaryText = adaptive(0xFFF8EF, 0x2C2520)
    static let shadow = rgb(0x2C2520)
    static let destructive = adaptive(0x9B4E40, 0xDCA391)
}

extension Color {
    static let questAccent = Color(uiColor: QuestPalette.link)
    static let questBackground = Color(uiColor: QuestPalette.background)
    static let questSurface = Color(uiColor: QuestPalette.surface)
    static let questRaised = Color(uiColor: QuestPalette.raised)
    static let questClay = Color(uiColor: QuestPalette.clay)
    static let questAmber = Color(uiColor: QuestPalette.amber)
    static let questSoft = Color(uiColor: QuestPalette.soft)
    static let questText = Color(uiColor: QuestPalette.text)
    static let questSecondary = Color(uiColor: QuestPalette.secondary)
    static let questBorder = Color(uiColor: QuestPalette.border)
    static let questSuccess = Color(uiColor: QuestPalette.success)
    static let questShadow = Color(uiColor: QuestPalette.shadow)
    static let questDestructive = Color(uiColor: QuestPalette.destructive)
}

extension View {
    func questCard() -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.questSurface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.questBorder, lineWidth: 1))
            .shadow(color: .questShadow.opacity(0.065), radius: 20, y: 8)
    }
    func questScreen() -> some View {
        font(.system(.body, design: .rounded)).foregroundStyle(Color.questText)
            .tint(.questAccent).background(Color.questBackground)
    }
}

struct QuestPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded))
            .padding(.horizontal, 20).padding(.vertical, 12).frame(minHeight: 52)
            .foregroundStyle(Color(uiColor: QuestPalette.primaryText))
            .background(Color(uiColor: QuestPalette.primaryFill).opacity(enabled ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .questShadow.opacity(enabled ? 0.08 : 0), radius: 16, y: 6)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.985 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
struct QuestSecondaryButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 10).frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(configuration.role == .destructive ? Color.questDestructive : .questText)
            .background((configuration.isPressed || selected) ? Color.questSoft : .questRaised, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(selected ? Color.questClay : .questBorder, lineWidth: selected ? 2 : 1))
            .opacity(enabled ? 1 : 0.5)
    }
}

struct QuestBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.title3).foregroundStyle(Color.questText).padding(14)
                .background(Color.questSoft, in: RoundedRectangle(cornerRadius: 19))
                .overlay(RoundedRectangle(cornerRadius: 19).stroke(Color.questBorder))
            VStack(alignment: .leading, spacing: 2) {
                Text("SideQuest").font(.system(.title2, design: .rounded, weight: .bold))
                Text("Good company. Little adventures.").font(.system(.caption, design: .rounded)).foregroundStyle(Color.questSecondary)
            }
        }
    }
}
