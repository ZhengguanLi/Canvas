import XCTest
@testable import ProjectCanvas

@MainActor
final class ClipboardPinTests: XCTestCase {
    private func defaults() throws -> (UserDefaults, String) {
        let name = "ClipboardPinTests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testPinnedTextsSortFirstSurviveLimitsAndClear() throws {
        let (preferences, name) = try defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        let history = ClipboardHistory(limit: 2, preferences: preferences)
        history.receiveText("a")
        history.receiveText("b")
        history.togglePin(text: try XCTUnwrap(history.texts.first { $0.text == "a" }).id)
        XCTAssertEqual(history.texts.map(\.text), ["a", "b"])
        history.receiveText("c")
        history.receiveText("d")
        // Pinned "a" stays first and does not count toward the limit of two.
        XCTAssertEqual(history.texts.map(\.text), ["a", "d", "c"])
        history.receiveText("a")
        XCTAssertEqual(history.texts.map(\.text), ["a", "d", "c"])
        history.clearTexts()
        XCTAssertEqual(history.texts.map(\.text), ["a"])
    }

    func testPinnedTextsPersistAndDeleteRemovesThem() throws {
        let (preferences, name) = try defaults()
        defer { preferences.removePersistentDomain(forName: name) }
        let history = ClipboardHistory(preferences: preferences)
        history.receiveText("keep me")
        let id = try XCTUnwrap(history.texts.first).id
        history.togglePin(text: id)
        let reloaded = ClipboardHistory(preferences: preferences)
        XCTAssertEqual(reloaded.texts.map(\.text), ["keep me"])
        XCTAssertTrue(reloaded.texts[0].isPinned)
        reloaded.removeText(reloaded.texts[0].id)
        XCTAssertTrue(ClipboardHistory(preferences: preferences).texts.isEmpty)
        history.togglePin(text: id)
        XCTAssertFalse(history.texts[0].isPinned)
    }
}
