import XCTest
@testable import ProjectCanvas

final class StorageTests: XCTestCase {
    func testCorruptDataIsPreservedUntilRecovery() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        let broken = Data("not json".utf8)
        try broken.write(to: url)
        let storage = CanvasStorage(url: url)
        XCTAssertThrowsError(try storage.load())
        XCTAssertThrowsError(try storage.save(.empty))
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }

    func testLegacyDataDefaultsAndFutureVersionIsRejected() throws {
        let legacy = Data(#"{"projects":[],"groups":[]}"#.utf8)
        XCTAssertEqual(try CanvasStorage.decode(legacy).schemaVersion, 1)
        XCTAssertThrowsError(try CanvasStorage.decode(Data(#"{"schemaVersion":99,"projects":[],"groups":[]}"#.utf8)))
    }

    func testBackupsRestoreLastValidatedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = CanvasStorage(url: directory.appendingPathComponent("canvas.json"))
        var first = ProjectCanvasData.empty
        first.groups[0].name = "before"
        try storage.save(first)
        var second = first
        second.groups[0].name = "after"
        try storage.save(second)
        try Data("broken".utf8).write(to: storage.url)
        XCTAssertEqual(try storage.restoreBackup().groups[0].name, "before")
        XCTAssertEqual(try storage.load()?.groups[0].name, "before")
    }

    func testLaunchArgumentsKeepPathsLiteral() {
        XCTAssertEqual(ProjectLauncher.arguments(editor: .vscode, newWindow: true, path: "/tmp/a; b"), ["--new-window", "/tmp/a; b"])
        XCTAssertEqual(ProjectLauncher.arguments(editor: .cursor, newWindow: false, path: "/tmp/a"), ["--reuse-window", "/tmp/a"])
    }

    func testGitParserIncludesBranchAndChanges() {
        let status = GitStatus.parse("## feature...origin/feature\n M file\n?? new\n", isWorktree: true)
        XCTAssertEqual(status.branch, "feature")
        XCTAssertEqual(status.changedFiles, 2)
        XCTAssertTrue(status.isWorktree)
    }
    func testInvalidReferencesAreRejected() throws {
        var data = ProjectCanvasData.empty
        data.groups[0].cards.append(ProjectCard(projectID: UUID(), x: 20, y: 20))
        XCTAssertThrowsError(try CanvasStorage.decode(JSONEncoder().encode(data)))
    }

    func testRestoreWithoutBackupLeavesDamagedDataUntouched() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        let bytes = Data("broken".utf8)
        try bytes.write(to: url)
        let storage = CanvasStorage(url: url)
        XCTAssertThrowsError(try storage.restoreBackup())
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }

}
