import XCTest
@testable import ProjectCanvas

final class IntegrationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @MainActor func testExportImportPreservesColorEdgesAndRemapsOnlyPathBoundary() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        let old = directory.appendingPathComponent("old")
        let oldish = directory.appendingPathComponent("oldish")
        try FileManager.default.createDirectory(at: old.appendingPathComponent("one"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: oldish.appendingPathComponent("two"), withIntermediateDirectories: true)
        model.addProject(folderURL: old.appendingPathComponent("one"))
        model.addProject(folderURL: oldish.appendingPathComponent("two"))
        let original = try XCTUnwrap(model.selectedGroup)
        let a = original.cards[0].id, b = original.cards[1].id
        model.setCardColor(.purple, ids: [a], in: original.id)
        model.connectCards(a, b, in: original.id)
        let edgeID = try XCTUnwrap(model.selectedGroup?.connections.first?.id)
        model.updateConnection(edgeID, in: original.id, kind: .call, label: "API")
        let exported = directory.appendingPathComponent("group.json")
        model.exportGroup(original.id, to: exported)
        model.importGroups(from: exported, pathFrom: old.path, pathTo: "/new")
        let imported = try XCTUnwrap(model.selectedGroup)
        XCTAssertNotEqual(imported.id, original.id)
        XCTAssertTrue(Set(imported.cards.map(\.id)).isDisjoint(with: original.cards.map(\.id)))
        XCTAssertEqual(imported.cards[0].color, .purple)
        XCTAssertEqual(imported.connections[0].kind, .call)
        XCTAssertEqual(imported.connections[0].label, "API")
        XCTAssertEqual(model.project(for: imported.cards[0])?.folderPath, "/new/one")
        XCTAssertEqual(model.project(for: imported.cards[1])?.folderPath, oldish.appendingPathComponent("two").path)
        XCTAssertTrue(imported.cards.contains(where: { $0.id == imported.connections[0].fromCardID }))
        model.undo()
        XCTAssertEqual(model.groups.count, 1)
        model.redo()
        XCTAssertEqual(model.groups.count, 2)
    }

    @MainActor func testViewportColorAndEditorPersist() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        defer { model.flushPersistence() }
        model.addProject(folderURL: directory)
        let group = try XCTUnwrap(model.selectedGroup)
        model.setCardColor(.green, ids: [group.cards[0].id], in: group.id)
        model.setProjectOpening(model.projects[0].id, editor: .cursor, newWindow: true)
        model.defaultEditor = .intellij
        model.updateViewport(CanvasViewport(zoom: 0.8, offsetX: 300, offsetY: 120), in: group.id)
        model.flushPersistence()
        let loaded = AppModel(storageURL: url)
        XCTAssertEqual(loaded.selectedGroup?.cards[0].color, .green)
        XCTAssertEqual(loaded.projects[0].editor, .cursor)
        XCTAssertEqual(loaded.projects[0].openInNewWindow, true)
        XCTAssertEqual(loaded.defaultEditor, .intellij)
        XCTAssertEqual(loaded.selectedGroup?.viewport, CanvasViewport(zoom: 0.8, offsetX: 300, offsetY: 120))
    }

    @MainActor func testBulkDeleteIsOneUndoAndPreservesOtherConnections() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        for name in ["a", "b", "c"] {
            let folder = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            model.addProject(folderURL: folder)
        }
        let group = try XCTUnwrap(model.selectedGroup)
        model.connectCards(group.cards[0].id, group.cards[1].id, in: group.id)
        model.connectCards(group.cards[1].id, group.cards[2].id, in: group.id)
        model.removeCards(Set(group.cards.prefix(2).map(\.id)), from: group.id)
        XCTAssertEqual(model.selectedGroup?.cards.count, 1)
        XCTAssertEqual(model.selectedGroup?.connections.count, 0)
        model.undo()
        XCTAssertEqual(model.selectedGroup?.cards.count, 3)
        XCTAssertEqual(model.selectedGroup?.connections.count, 2)
    }

    func testTransitiveRelationsTerminateOnCycles() {
        let a = ProjectCard(projectID: UUID(), x: 0, y: 0)
        let b = ProjectCard(projectID: UUID(), x: 0, y: 0)
        let c = ProjectCard(projectID: UUID(), x: 0, y: 0)
        let group = ProjectGroup(name: "graph", cards: [a,b,c], connections: [
            ProjectConnection(fromCardID: a.id, toCardID: b.id),
            ProjectConnection(fromCardID: b.id, toCardID: c.id),
            ProjectConnection(fromCardID: c.id, toCardID: a.id)
        ])
        XCTAssertEqual(group.relatedCardIDs(to: [a.id], upstream: false), [b.id,c.id])
        XCTAssertEqual(group.relatedCardIDs(to: [a.id], upstream: true), [b.id,c.id])
    }

    func testLegacyCardsAndConnectionsDefaultWithoutLosingLayout() throws {
        let data = Data(#"{"projects":[{"id":"00000000-0000-0000-0000-000000000001","folderPath":"/tmp"}],"groups":[{"id":"00000000-0000-0000-0000-000000000002","name":"legacy","cards":[{"id":"00000000-0000-0000-0000-000000000003","projectID":"00000000-0000-0000-0000-000000000001","x":100,"y":200}],"connections":[],"showsConnections":false}]}"#.utf8)
        let loaded = try CanvasStorage.decode(data)
        XCTAssertEqual(loaded.groups[0].cards[0].color, .neutral)
        XCTAssertEqual(loaded.groups[0].cards[0].y, 200)
        XCTAssertNil(loaded.projects[0].editor)
    }

    func testGitNulParserCountsRenameOnceAndKeepsNewlinesInFilename() {
        let status = GitStatus.parse("## main\0R  new\0old\0?? name\nwithnewline\0", isWorktree: false)
        XCTAssertEqual(status.branch, "main")
        XCTAssertEqual(status.changedFiles, 2)
    }

    func testReadActualGitRepositoryAndLinkedWorktree() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        func git(_ arguments: [String]) throws {
            let result = try ProcessRunner.run(executable: "/usr/bin/git", arguments: arguments, directory: directory)
            XCTAssertEqual(result.status, 0, result.output)
        }
        try git(["init", "-b", "main"])
        try Data("hello".utf8).write(to: directory.appendingPathComponent("file"))
        try git(["add", "file"])
        try git(["-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-m", "initial"])
        XCTAssertEqual(GitStatus.read(at: directory).changedFiles, 0)
        let linked = directory.appendingPathComponent("linked")
        try git(["worktree", "add", "-b", "feature", linked.path])
        try Data("changed".utf8).write(to: linked.appendingPathComponent("file"))
        let status = GitStatus.read(at: linked)
        XCTAssertEqual(status.branch, "feature")
        XCTAssertEqual(status.changedFiles, 1)
        XCTAssertTrue(status.isWorktree)
    }

    func testMissingDirectoryLaunchReportsFailure() async throws {
        let project = Project(folderURL: URL(fileURLWithPath: "/missing-\(UUID().uuidString)"))
        do {
            try await ProjectLauncher.open(project, editor: .finder, newWindow: false)
            XCTFail("Missing directory should fail before launching any app")
        } catch { XCTAssertEqual(error.localizedDescription, ProjectLauncher.LaunchError.missingFolder.localizedDescription) }
    }
}
