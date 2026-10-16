import XCTest
@testable import ProjectCanvas

final class DesktopOverlayLayoutTests: XCTestCase {
    func testFullScreenShelfFillsAvailableSpaceWithoutChangingCardLayout() {
        let visible = CGRect(x: -1200, y: 100, width: 1000, height: 700)
        let normal = DesktopOverlayLayout(visibleFrame: visible, expanded: true)
        let full = DesktopOverlayLayout(visibleFrame: visible, expanded: true, fullScreen: true)
        XCTAssertEqual(full.shelf, visible.insetBy(dx: 24, dy: 24))
        XCTAssertEqual(full.cards, normal.cards)
        XCTAssertGreaterThan(full.shelf.height, normal.shelf.height)
    }

    func testClipboardShelfIsAtTopWithoutOverlappingCardsOnOffsetMonitor() {
        let visible = CGRect(x: -1200, y: -200, width: 1000, height: 700)
        let layout = DesktopOverlayLayout(visibleFrame: visible, expanded: true)
        XCTAssertTrue(visible.contains(layout.shelf))
        XCTAssertTrue(visible.contains(layout.cards))
        XCTAssertLessThan(layout.cards.maxY, layout.shelf.minY)
        XCTAssertEqual(layout.shelf.maxY, visible.maxY - 24)
        let compact = DesktopOverlayLayout(visibleFrame: visible, expanded: false)
        XCTAssertGreaterThan(compact.cards.height, layout.cards.height)
        XCTAssertEqual(compact.shelf.maxY, layout.shelf.maxY)
    }
}
