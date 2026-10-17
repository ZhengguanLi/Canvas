import AppKit
import Carbon
import XCTest
@testable import ProjectCanvas

final class HotKeyShortcutTests: XCTestCase {
    func testDefaultIsShiftCommandC() {
        XCTAssertEqual(HotKeyShortcut.default.keyCode, UInt16(kVK_ANSI_C))
        XCTAssertEqual(HotKeyShortcut.default.displayString, "⇧⌘C")
        XCTAssertEqual(HotKeyShortcut.default.carbonModifiers, UInt32(cmdKey | shiftKey))
    }

    func testDisplayOrderAndCarbonModifiers() {
        let shortcut = HotKeyShortcut(keyCode: UInt16(kVK_Space), modifiers: [.command, .control, .option, .shift, .capsLock], key: "Space")
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘Space")
        XCTAssertEqual(shortcut.carbonModifiers, UInt32(cmdKey | shiftKey | optionKey | controlKey))
    }

    func testRecordingRequiresCommandControlOrOption() {
        XCTAssertNil(HotKeyShortcut.from(keyCode: UInt16(kVK_ANSI_K), modifiers: [], characters: "k"))
        XCTAssertNil(HotKeyShortcut.from(keyCode: UInt16(kVK_ANSI_K), modifiers: .shift, characters: "K"))
        XCTAssertNil(HotKeyShortcut.from(keyCode: UInt16(kVK_Escape), modifiers: .command, characters: "\u{1b}"))
        XCTAssertEqual(HotKeyShortcut.from(keyCode: UInt16(kVK_ANSI_K), modifiers: [.option, .shift], characters: "k")?.displayString, "⌥⇧K")
        XCTAssertEqual(HotKeyShortcut.from(keyCode: UInt16(kVK_Space), modifiers: .control, characters: " ")?.displayString, "⌃Space")
        XCTAssertEqual(HotKeyShortcut.from(keyCode: UInt16(kVK_F5), modifiers: .command, characters: nil)?.key, "F5")
    }

    func testSaveLoadAndFallback() throws {
        let name = "HotKeyShortcutTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        XCTAssertEqual(HotKeyShortcut.load(from: preferences), .default)
        let custom = HotKeyShortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: [.command, .option], key: "D")
        custom.save(to: preferences)
        XCTAssertEqual(HotKeyShortcut.load(from: preferences), custom)
        // A stored shortcut without ⌘, ⌃ or ⌥ would capture plain typing, so it falls back.
        HotKeyShortcut(keyCode: UInt16(kVK_ANSI_D), modifiers: .shift, key: "D").save(to: preferences)
        XCTAssertEqual(HotKeyShortcut.load(from: preferences), .default)
        preferences.set(Data("junk".utf8), forKey: HotKeyShortcut.preferenceKey)
        XCTAssertEqual(HotKeyShortcut.load(from: preferences), .default)
    }
}
