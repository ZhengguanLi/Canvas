import XCTest
@testable import ProjectCanvas

final class DesktopOverlayLayoutTests: XCTestCase {
    func testWideShelfUsesScreenWidthWithoutChangingHeightOrCardLayout() {
        let visible = CGRect(x: -1200, y: 100, width: 1800, height: 700)
        let normal = DesktopOverlayLayout(visibleFrame: visible, expanded: true)
        let full = DesktopOverlayLayout(visibleFrame: visible, expanded: true, fullWidth: true)
        XCTAssertEqual(full.shelf.width, visible.width - 48)
        XCTAssertEqual(full.shelf.height, normal.shelf.height)
        XCTAssertEqual(full.shelf.maxY, normal.shelf.maxY)
        XCTAssertEqual(full.cards, normal.cards)
        XCTAssertGreaterThan(full.shelf.width, normal.shelf.width)
    }

    func testFullScreenClipboardFillsAvailableSpaceAndPreservesCards() {
        let visible = CGRect(x: -1200, y: 100, width: 1800, height: 700)
        let normal = DesktopOverlayLayout(visibleFrame: visible, expanded: true)
        let full = DesktopOverlayLayout(visibleFrame: visible, expanded: true, fullScreen: true)
        XCTAssertEqual(full.shelf, visible.insetBy(dx: 24, dy: 24))
        XCTAssertEqual(full.cards, normal.cards)
    }

    @MainActor func testEscapeRestoresClipboardSizeBeforeDesktopDismissal() throws {
        let name = "ClipboardEscapeTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        XCTAssertFalse(DesktopDisplayController.restoreClipboardSize(in: preferences))
        preferences.set(true, forKey: "clipboardShelfFullWidth")
        XCTAssertFalse(DesktopDisplayController.restoreClipboardSize(in: preferences))
        preferences.set(true, forKey: "clipboardShelfFullScreen")
        XCTAssertTrue(DesktopDisplayController.restoreClipboardSize(in: preferences))
        XCTAssertFalse(preferences.bool(forKey: "clipboardShelfFullScreen"))
        XCTAssertTrue(preferences.bool(forKey: "clipboardShelfFullWidth"))
        XCTAssertFalse(DesktopDisplayController.restoreClipboardSize(in: preferences))
        preferences.set(false, forKey: "clipboardShelfVisible")
        preferences.set(true, forKey: "clipboardShelfFullScreen")
        XCTAssertFalse(DesktopDisplayController.restoreClipboardSize(in: preferences))
    }

    func testHiddenClipboardReservesNoSpaceAboveCards() {
        let visible = CGRect(x: -800, y: 100, width: 1440, height: 900)
        let layout = DesktopOverlayLayout(visibleFrame: visible, expanded: true, visible: false)
        XCTAssertEqual(layout.shelf, .zero)
        XCTAssertEqual(layout.cards, visible.insetBy(dx: 24, dy: 24))
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
