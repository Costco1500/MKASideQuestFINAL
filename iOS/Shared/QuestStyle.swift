import SwiftUI

/// All SideQuest colors adapt independently to warm light and dark appearances.
enum QuestPalette {
    private static func rgb(_ hex: UInt) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    private static func adaptive(_ light: UInt, _ dark: UInt) -> UIColor {
        UIColor { traits in rgb(traits.userInterfaceStyle == .dark ? dark : light) }
    }
    static let background = adaptive(0xFBF3EA, 0x17110E)
    static let glow = adaptive(0xFFE3C8, 0x3A2216)
    static let surface = adaptive(0xFFFCF8, 0x231B16)
    static let raised = adaptive(0xFFF4E9, 0x2E231D)
    static let clay = adaptive(0xD2693F, 0xE58A5E)
    static let amber = adaptive(0xE9A23B, 0xF0B25A)
    static let soft = adaptive(0xFBE3CB, 0x4A3222)
    static let text = adaptive(0x2A1F1A, 0xF7ECDF)
    static let secondary = adaptive(0x7A6558, 0xC2AE9E)
    static let border = adaptive(0xEFDFCF, 0x3C2E25)
    static let success = adaptive(0x3F7A4E, 0x9CCB9F)
    static let warning = adaptive(0x9A5B0E, 0xF0B25A)
    static let link = adaptive(0xA8452A, 0xF2A37A)
    // Buttons: white on deep terracotta in light mode, espresso on apricot in dark mode.
    static let primaryFill = adaptive(0xB6452B, 0xEC8F5F)
    static let primaryStart = adaptive(0xC9502C, 0xF3A46C)
    static let primaryEnd = adaptive(0xA3392B, 0xE57C52)
    static let primaryText = adaptive(0xFFFFFF, 0x221710)
    static let shadow = rgb(0x5A3420)
    static let destructive = adaptive(0xA83A30, 0xEE9A8C)
    // Hero sunset: amber into ember into plum. White text only at large sizes over the lightest stop.
    static let sunset = [rgb(0xE8743B), rgb(0xCF4F3C), rgb(0x9E3656)]
}

extension Color {
    static let questAccent = Color(uiColor: QuestPalette.link)
    static let questBackground = Color(uiColor: QuestPalette.background)
    static let questGlow = Color(uiColor: QuestPalette.glow)
    static let questSurface = Color(uiColor: QuestPalette.surface)
    static let questRaised = Color(uiColor: QuestPalette.raised)
    static let questClay = Color(uiColor: QuestPalette.clay)
    static let questAmber = Color(uiColor: QuestPalette.amber)
    static let questSoft = Color(uiColor: QuestPalette.soft)
    static let questText = Color(uiColor: QuestPalette.text)
    static let questSecondary = Color(uiColor: QuestPalette.secondary)
    static let questBorder = Color(uiColor: QuestPalette.border)
    static let questSuccess = Color(uiColor: QuestPalette.success)
    static let questWarning = Color(uiColor: QuestPalette.warning)
    static let questShadow = Color(uiColor: QuestPalette.shadow)
    static let questDestructive = Color(uiColor: QuestPalette.destructive)
}

extension ShapeStyle where Self == LinearGradient {
    static var questPrimary: LinearGradient {
        LinearGradient(colors: [Color(uiColor: QuestPalette.primaryStart), Color(uiColor: QuestPalette.primaryEnd)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var questSunset: LinearGradient {
        LinearGradient(colors: QuestPalette.sunset.map { Color(uiColor: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    func questCard(padding: CGFloat = 20) -> some View {
        self.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.questSurface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(Color.questBorder.opacity(0.8), lineWidth: 1))
            .shadow(color: .questShadow.opacity(0.08), radius: 24, y: 10)
    }
    func questScreen() -> some View {
        font(.system(.body, design: .rounded)).foregroundStyle(Color.questText)
            .tint(.questAccent).background(QuestBackdrop())
    }
}

/// Cream page with a soft apricot glow at the top.
struct QuestBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.questBackground
            RadialGradient(colors: [.questGlow, .questGlow.opacity(0)], center: .topTrailing, startRadius: 10, endRadius: 420)
                .frame(height: 460)
        }.ignoresSafeArea()
    }
}

struct QuestPrimaryButtonStyle: ButtonStyle {
    var fullWidth = true
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.headline, design: .rounded))
            .padding(.horizontal, 22).padding(.vertical, 14).frame(maxWidth: fullWidth ? .infinity : nil, minHeight: 54)
            .foregroundStyle(Color(uiColor: QuestPalette.primaryText))
            .background(.questPrimary, in: Capsule())
            .opacity(enabled ? 1 : 0.45)
            .shadow(color: Color(uiColor: QuestPalette.primaryEnd).opacity(enabled ? 0.3 : 0), radius: 14, y: 7)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

struct QuestSecondaryButtonStyle: ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .rounded, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 11).frame(minWidth: 44, minHeight: 46)
            .foregroundStyle(configuration.role == .destructive ? Color.questDestructive : .questText)
            .background((configuration.isPressed || selected) ? Color.questSoft : .questRaised, in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.questClay : .questBorder, lineWidth: selected ? 2 : 1))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.97 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// App mark: a sunset tile with a sparkle, used wherever the SideQuest name appears.
struct QuestLogo: View {
    var size: CGFloat = 46
    var body: some View {
        Image(systemName: "sparkles").font(.system(size: size * 0.42, weight: .bold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(.questSunset, in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
            .shadow(color: Color(uiColor: QuestPalette.sunset[1]).opacity(0.35), radius: 10, y: 5)
            .accessibilityHidden(true)
    }
}

struct QuestBrand: View {
    var body: some View {
        HStack(spacing: 12) {
            QuestLogo()
            VStack(alignment: .leading, spacing: 2) {
                Text("SideQuest").font(.system(.title2, design: .rounded, weight: .heavy))
                Text("Good company. Little adventures.").font(.system(.caption, design: .rounded, weight: .medium)).foregroundStyle(Color.questSecondary)
            }
        }
    }
}
