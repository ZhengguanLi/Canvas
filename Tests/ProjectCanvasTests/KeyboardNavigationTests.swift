import AppKit
import XCTest
@testable import ProjectCanvas

final class KeyboardNavigationTests: XCTestCase {
    private func card(_ x: Double, _ y: Double) -> ProjectCard { ProjectCard(clipboard: .note(""), x: x, y: y) }

    func testArrowPicksNearestCardInDirection() {
        let a = card(100, 100), right = card(400, 110), farRight = card(700, 100), below = card(110, 300), diagonal = card(380, 400)
        let cards = [a, right, farRight, below, diagonal]
        XCTAssertEqual(CanvasNavigation.next(from: a, direction: .right, in: cards)?.id, right.id)
        XCTAssertEqual(CanvasNavigation.next(from: a, direction: .down, in: cards)?.id, below.id)
        XCTAssertNil(CanvasNavigation.next(from: a, direction: .left, in: cards))
        XCTAssertNil(CanvasNavigation.next(from: a, direction: .up, in: cards))
        XCTAssertEqual(CanvasNavigation.next(from: right, direction: .right, in: cards)?.id, farRight.id)
        // With nothing selected, start from the top-left card.
        XCTAssertEqual(CanvasNavigation.next(from: nil, direction: .down, in: cards)?.id, a.id)
    }

    func testKeyMapping() throws {
        func event(_ code: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0,
                                          context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                          isARepeat: false, keyCode: code))
        }
        XCTAssertEqual(CanvasInputSupport.key(for: try event(124, "")), .arrow(.right))
        XCTAssertEqual(CanvasInputSupport.key(for: try event(36, "\r")), .open)
        XCTAssertEqual(CanvasInputSupport.key(for: try event(2, "d", .command)), .duplicate)
        XCTAssertNil(CanvasInputSupport.key(for: try event(124, "", .command)))
        XCTAssertNil(CanvasInputSupport.key(for: try event(2, "d")))
    }

    @MainActor func testDuplicateCopiesNoteAndClipboardCardsOnly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "KeyboardNavigationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"), preferences: preferences)
        let groupID = try XCTUnwrap(model.selectedGroupID)
        model.addProject(folderURL: directory)
        let noteID = try XCTUnwrap(model.addNote(to: groupID))
        model.updateNote(noteID, text: "copy me", in: groupID)
        model.setCardColor(.pink, ids: [noteID], in: groupID)
        let projectCardID = try XCTUnwrap(model.selectedGroup?.cards.first { $0.projectID != nil }).id
        let copies = model.duplicateCards([noteID, projectCardID], in: groupID)
        XCTAssertEqual(copies.count, 1)
        let copy = try XCTUnwrap(model.selectedGroup?.cards.first { copies.contains($0.id) })
        XCTAssertEqual(copy.clipboard, .note("copy me"))
        XCTAssertEqual(copy.color, .pink)
        model.undo()
        XCTAssertFalse(model.selectedGroup?.cards.contains { copies.contains($0.id) } ?? true)
    }
}
