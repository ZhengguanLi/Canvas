import AppKit
import XCTest
@testable import ProjectCanvas

final class CanvasInputSupportTests: XCTestCase {
    func testControlAndShiftExtendSelection() {
        XCTAssertTrue(CanvasInputSupport.extendsSelection(.control))
        XCTAssertTrue(CanvasInputSupport.extendsSelection(.shift))
        XCTAssertTrue(CanvasInputSupport.extendsSelection([.control, .shift]))
        XCTAssertFalse(CanvasInputSupport.extendsSelection([]))
    }

    @MainActor func testSelectAllRecognizesControlAndCommandWithoutOtherShortcuts() throws {
        _ = NSApplication.shared
        for flags: NSEvent.ModifierFlags in [.control, .command, .option, [.control, .shift]] {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a",
                isARepeat: false, keyCode: 0))
            XCTAssertEqual(CanvasInputSupport.isSelectAll(event), flags == .control || flags == .command)
        }
    }

    @MainActor func testControlLeftClickBecomesSelectionWithoutChangingRealRightClicks() throws {
        _ = NSApplication.shared
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 20, y: 30),
                modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0))
            let normalized = try XCTUnwrap(CanvasInputSupport.normalizedMouseEvent(event))
            XCTAssertEqual(normalized.type, type)
            XCTAssertEqual(normalized.locationInWindow, event.locationInWindow)
            if type == .rightMouseDown {
                XCTAssertTrue(normalized === event)
            } else {
                XCTAssertFalse(normalized.modifierFlags.contains(.control))
                XCTAssertTrue(normalized.modifierFlags.contains(.shift))
            }
        }
    }
}
