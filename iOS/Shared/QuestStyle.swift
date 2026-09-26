import SwiftUI

extension Color {
    static let questAccent = Color(red: 0.28, green: 0.28, blue: 0.88)
    static let questBackground = Color(uiColor: .systemGroupedBackground)
}

extension View {
    func questCard() -> some View {
        padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 24))
    }
}

struct QuestBrand: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.white).padding(12)
                .background(Color.questAccent, in: RoundedRectangle(cornerRadius: 16))
            Text("SideQuest").font(.system(.title2, design: .rounded, weight: .bold))
        }
    }
}
