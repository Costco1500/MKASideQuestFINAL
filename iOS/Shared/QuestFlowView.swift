import SwiftUI

struct QuestFlowView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    QuestBrand()
                    Text("Your next hangout starts here.").font(.title.bold())
                    Text("You choose what SideQuest sees.").foregroundStyle(.secondary)
                }.padding(24)
            }.background(Color.questBackground)
        }.tint(.questAccent)
    }
}
