import XCTest
@testable import ProjectCanvas

final class ClipboardAppearanceTests: XCTestCase {
    func testIndependentSizesLoadFromPreferencesAndClampInvalidValues() throws {
        let name = "ClipboardAppearanceTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        XCTAssertEqual(ClipboardAppearance.load(from: preferences).textSize, 14)
        preferences.set(1.8, forKey: ClipboardAppearance.imageScaleKey)
        preferences.set(22.0, forKey: ClipboardAppearance.textSizeKey)
        let appearance = ClipboardAppearance.load(from: preferences)
        XCTAssertEqual(appearance.imageScale, 1.8)
        XCTAssertEqual(appearance.textSize, 22)
        let invalid = ClipboardAppearance(imageScale: .nan, textSize: .infinity)
        XCTAssertEqual(invalid.imageScale, 1.25)
        XCTAssertEqual(invalid.textSize, 14)
        XCTAssertEqual(ClipboardAppearance(imageScale: 100, textSize: -1).imageScale, 2)
        XCTAssertEqual(ClipboardAppearance(imageScale: 100, textSize: -1).textSize, 11)
    }

    func testLargerRowsReservePanelSpaceAboveCards() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 1000)
        let small = ClipboardAppearance(imageScale: 1, textSize: 11)
        let large = ClipboardAppearance(imageScale: 2, textSize: 24)
        let layout = DesktopOverlayLayout(visibleFrame: visible, expanded: true, shelfHeight: large.shelfHeight)
        XCTAssertEqual(layout.shelf.height, large.shelfHeight)
        XCTAssertGreaterThan(large.shelfHeight, small.shelfHeight)
        XCTAssertLessThan(layout.cards.maxY, layout.shelf.minY)
        XCTAssertTrue(visible.contains(layout.shelf))
    }
}
