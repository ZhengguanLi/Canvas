import XCTest
@testable import ProjectCanvas

final class AppModelTests: XCTestCase {
    @MainActor func testSelectionSurvivesRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        let first = model.selectedGroupID
        model.addGroup()
        model.selectedGroupID = first
        XCTAssertEqual(AppModel(storageURL: url).selectedGroupID, first)
    }

    @MainActor func testCorruptSourceIsNotOverwrittenByEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        let bytes = Data("broken".utf8)
        try bytes.write(to: url)
        let model = AppModel(storageURL: url)
        model.addGroup()
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertNotNil(model.alertMessage)
    }

    @MainActor func testDirectedReverseEdgesAndRemovalUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        model.addProject(folderURL: URL(fileURLWithPath: "/tmp"))
        model.addProject(folderURL: URL(fileURLWithPath: "/Applications"))
        let group = try XCTUnwrap(model.selectedGroup)
        let a = group.cards[0].id, b = group.cards[1].id
        model.connectCards(a, b, in: group.id)
        model.connectCards(b, a, in: group.id)
        XCTAssertEqual(model.selectedGroup?.connections.count, 2)
        model.removeCard(a, from: group.id)
        XCTAssertTrue(model.selectedGroup!.connections.isEmpty)
        model.undo()
        XCTAssertEqual(model.selectedGroup?.connections.count, 2)
        model.redo()
        XCTAssertTrue(model.selectedGroup!.connections.isEmpty)
    }
    @MainActor func testViewportUpdatesDoNotRotateAwayRecoveryHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model.addProject(folderURL: directory)
        let group = try XCTUnwrap(model.selectedGroup)
        model.setCardColor(.blue, ids: [group.cards[0].id], in: group.id)
        for x in 0...10 { model.updateViewport(CanvasViewport(zoom: 1, offsetX: Double(x * 100), offsetY: 0), in: group.id) }
        model.restoreBackup()
        XCTAssertEqual(model.selectedGroup?.cards.first?.color, .neutral)
    }

    @MainActor func testDuplicateFolderImportDoesNotConsumeUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        let groupID = try XCTUnwrap(model.selectedGroupID)
        model.addProjects(folderURLs: [directory], to: groupID)
        model.addProjects(folderURLs: [directory], to: groupID)
        model.undo()
        XCTAssertEqual(model.selectedGroup?.cards.count, 0)
    }

    @MainActor func testDeletingSelectedGroupRetainsRecoverableBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        model.addGroup()
        model.deleteGroup(model.selectedGroupID!)
        XCTAssertEqual(model.groups.count, 1)
        model.restoreBackup()
        XCTAssertEqual(model.groups.count, 2)
    }

    @MainActor func testImportCanRecoverFromCorruptFileWithoutDestroyingOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        let broken = Data("broken".utf8)
        try broken.write(to: url)
        let model = AppModel(storageURL: url)
        let incoming = directory.appendingPathComponent("import.json")
        try JSONEncoder().encode(ProjectCanvasData.empty).write(to: incoming)
        model.importGroups(from: incoming, pathFrom: "", pathTo: "")
        XCTAssertFalse(model.needsRecovery)
        XCTAssertNoThrow(try CanvasStorage.decode(Data(contentsOf: url)))
        let preserved = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.contains("preserved-") }
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(preserved)), broken)
    }

}
