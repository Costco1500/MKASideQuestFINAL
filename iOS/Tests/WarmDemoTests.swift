import XCTest
import UIKit
@testable import SideQuest
@testable import SideQuestCore

final class WarmDemoTests: XCTestCase {
    func testConversationFeelsLikeAGroupAndUsesExistingSelection() {
        var messages = DemoConversation.messages
        XCTAssertTrue((30...40).contains(messages.count))
        XCTAssertEqual(Set(messages.map(\.sender)), Set(["Alex", "Maya", "Jake", "Sarah"]))
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("pottery") })
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("boba") })
        XCTAssertTrue(messages.contains { $0.text.localizedCaseInsensitiveContains("laundry") })
        messages += MessageImport.parse((0..<30).map { "Alex: extra \($0)" }.joined(separator: "\n"))
        MessageImport.select(.latest50, in: &messages)
        XCTAssertEqual(messages.filter(\.isSelected).count, 50)
        XCTAssertEqual(MessageImport.analysisMessages(messages).count, 50)
    }
    func testWarmColorsAreReadableInLightAndDarkMode() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let background = QuestPalette.background.resolvedColor(with: traits)
            let text = QuestPalette.text.resolvedColor(with: traits)
            let fill = QuestPalette.primaryFill.resolvedColor(with: traits)
            let buttonText = QuestPalette.primaryText.resolvedColor(with: traits)
            XCTAssertGreaterThan(contrast(background, text), 7)
            XCTAssertGreaterThanOrEqual(contrast(fill, buttonText), 4.5)
            XCTAssertNotEqual(background, .black)
            XCTAssertNotEqual(background, .white)
        }
    }
    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            let linear = [r,g,b].map { v -> Double in let d = Double(v); return d <= 0.04045 ? d / 12.92 : pow((d + 0.055) / 1.055, 2.4) }
            return linear[0] * 0.2126 + linear[1] * 0.7152 + linear[2] * 0.0722
        }
        let x = luminance(a), y = luminance(b)
        return (max(x,y) + 0.05) / (min(x,y) + 0.05)
    }
}
