import XCTest
@testable import ProjectCanvas

final class NoteCardTests: XCTestCase {
    @MainActor private func withModel(_ body: (AppModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "NoteCardTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer {
            preferences.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        try body(AppModel(storageURL: url, preferences: preferences), url)
    }

    @MainActor func testAddEditUndoAndPersistNote() throws {
        try withModel { model, url in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            let id = try XCTUnwrap(model.addNote(to: groupID))
            XCTAssertEqual(model.selectedGroup?.cards.first { $0.id == id }?.clipboard, .note(""))
            model.updateNote(id, text: "**Ship** it", in: groupID)
            XCTAssertEqual(model.selectedGroup?.cards.first { $0.id == id }?.clipboard, .note("**Ship** it"))
            model.undo()
            XCTAssertEqual(model.selectedGroup?.cards.first { $0.id == id }?.clipboard, .note(""))
            model.redo()
            model.flushPersistence()
            let reloaded = AppModel(storageURL: url, preferences: try XCTUnwrap(UserDefaults(suiteName: "NoteCardTests.reload.\(UUID().uuidString)")))
            XCTAssertEqual(reloaded.groups.flatMap(\.cards).first { $0.id == id }?.clipboard, .note("**Ship** it"))
        }
    }

    func testNoteTitleCopyAndMarkdown() {
        XCTAssertEqual(CanvasClipboardContent.note("First line\nSecond").title, "First line")
        XCTAssertTrue(CanvasClipboardContent.note("").isValid)
        XCTAssertTrue(CanvasClipboardContent.note("x").isNote)
        XCTAssertFalse(CanvasClipboardContent.text("x").isNote)
        XCTAssertEqual(String(CanvasClipboardTile.markdown("**bold** text").characters), "bold text")
    }

    func testLegacyContentStillDecodes() throws {
        let data = try JSONEncoder().encode(CanvasClipboardContent.text("legacy"))
        XCTAssertEqual(try JSONDecoder().decode(CanvasClipboardContent.self, from: data), .text("legacy"))
        let note = try JSONEncoder().encode(CanvasClipboardContent.note("n"))
        XCTAssertEqual(try JSONDecoder().decode(CanvasClipboardContent.self, from: note), .note("n"))
    }
}
