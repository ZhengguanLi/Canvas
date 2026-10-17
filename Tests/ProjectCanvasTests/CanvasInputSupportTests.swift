import AppKit
import XCTest
@testable import ProjectCanvas

final class CanvasInputSupportTests: XCTestCase {
    func testCommandAndShiftExtendSelection() {
        XCTAssertTrue(CanvasInputSupport.extendsSelection(.command))
        XCTAssertTrue(CanvasInputSupport.extendsSelection(.shift))
        XCTAssertTrue(CanvasInputSupport.extendsSelection([.command, .shift]))
        // Control-click is the native context-menu gesture, so it does not extend the selection.
        XCTAssertFalse(CanvasInputSupport.extendsSelection(.control))
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
}
