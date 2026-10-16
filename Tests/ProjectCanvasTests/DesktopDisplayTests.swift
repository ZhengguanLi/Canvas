import AppKit
import SwiftUI
import XCTest
@testable import ProjectCanvas

final class DesktopDisplayTests: XCTestCase {
    @MainActor func testBlurAndConnectionsFillScreenWhenDesktopDisplayIsEnabled() async throws {
        _ = NSApplication.shared
        guard let screen = DesktopPreferences.selectedScreen else { throw XCTSkip("Requires a macOS window-server session") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suiteName = "ProjectCanvasTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer {
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"), preferences: preferences)
        model.addProject(folderURL: directory)
        model.setDesktopDisplayMode(.foregroundOverlay)
        model.toggleDesktopDisplay()
        defer { if model.isDesktopDisplayOn { model.toggleDesktopDisplay() } }
        try await Task.sleep(for: .milliseconds(100))
        let background = try XCTUnwrap(NSApp.windows.first { $0.contentView is DesktopBackgroundBlurView })
        let blur = try XCTUnwrap(background.contentView as? DesktopBackgroundBlurView)
        let shelf = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView is NSHostingView<ClipboardShelfView> })
        XCTAssertFalse(shelf.ignoresMouseEvents)
        XCTAssertFalse(shelf.canBecomeKey)
        for cardPanel in NSApp.windows where cardPanel.isVisible && cardPanel.contentView is DesktopProjectCardView {
            XCTAssertLessThan(cardPanel.frame.maxY, shelf.frame.minY)
        }
        XCTAssertTrue(background.isVisible, "Enabling cards must also show the blur")
        XCTAssertEqual(blur.bounds.width, screen.frame.width, accuracy: 1)
        XCTAssertEqual(blur.bounds.height, screen.frame.height, accuracy: 1)
        let drawing = try XCTUnwrap(blur.subviews.first { $0 is DesktopConnectionView })
        XCTAssertEqual(drawing.frame.size, blur.bounds.size)
        XCTAssertFalse(background.ignoresMouseEvents)
        XCTAssertEqual(blur.effect.blendingMode, .behindWindow)
        XCTAssertEqual(blur.effect.state, .active)
        blur.update(appearance: DesktopAppearance(blur: 0, dimming: 0.4))
        XCTAssertTrue(blur.effect.isHidden)
        XCTAssertEqual(blur.connections.alphaValue, 1)
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: CGPoint(x: 12, y: 12), modifierFlags: [], timestamp: 0, windowNumber: background.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        XCTAssertTrue(blur.hitTest(CGPoint(x: 12, y: 12)) === blur, "Background decorations must not intercept dismissal")
        blur.mouseUp(with: click)
        XCTAssertFalse(model.isDesktopDisplayOn)
        XCTAssertFalse(background.isVisible)
        XCTAssertFalse(shelf.isVisible)
    }
}
