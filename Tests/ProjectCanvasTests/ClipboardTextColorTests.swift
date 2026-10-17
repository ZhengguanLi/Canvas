import XCTest
@testable import ProjectCanvas

final class ClipboardTextColorTests: XCTestCase {
    func testFollowUsesLastAllCardsColorAndExplicitChoiceWins() {
        let follow = ClipboardAppearance.followCardsColor
        XCTAssertEqual(ClipboardAppearance.textCardColor(choice: follow, lastAllCards: "blue"), .blue)
        XCTAssertEqual(ClipboardAppearance.textCardColor(choice: follow, lastAllCards: "neutral"), .neutral)
        XCTAssertEqual(ClipboardAppearance.textCardColor(choice: "pink", lastAllCards: "blue"), .pink)
        XCTAssertEqual(ClipboardAppearance.textCardColor(choice: "invalid", lastAllCards: "blue"), .neutral)
    }
}
