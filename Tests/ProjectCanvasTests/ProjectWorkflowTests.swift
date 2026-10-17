import XCTest
@testable import ProjectCanvas

final class ProjectWorkflowTests: XCTestCase {
    @MainActor func testTagsFilterWithoutChangingLayoutAndPersistAcrossGroups() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        defer { model.flushPersistence() }
        model.addProject(folderURL: dir)
        let project = try XCTUnwrap(model.projects.first)
        let group = try XCTUnwrap(model.selectedGroup)
        XCTAssertTrue(model.saveProjectWorkflow(project.id, tags: [" API ", "api", "", "Backend"], configurations: []))
        XCTAssertEqual(model.projects[0].tags, ["API", "Backend"])
        XCTAssertEqual(model.searchProjects("backend").count, 1)
        XCTAssertEqual(model.filteredGroup(group, tag: "api").cards, group.cards)
        XCTAssertTrue(model.filteredGroup(group, tag: "missing").cards.isEmpty)
        XCTAssertEqual(model.selectedGroup?.cards, group.cards)
        model.addGroup()
        model.addProject(folderURL: dir)
        XCTAssertEqual(model.searchProjects("backend").count, 2)
        model.flushPersistence()
        XCTAssertEqual(AppModel(storageURL: url).projects[0].tags, ["API", "Backend"])
    }

    @MainActor func testUsageSurvivesUndoAndRanksUniqueVisibleProjects() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        defer { model.flushPersistence() }
        model.addProject(folderURL: dir)
        let id = try XCTUnwrap(model.projects.first?.id)
        model.recordProjectOpened(id, at: Date(timeIntervalSince1970: 100))
        model.addGroup()
        model.addProject(folderURL: dir)
        model.recordProjectOpened(id, at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(model.recentProjects.count, 1)
        XCTAssertEqual(model.frequentProjects.first?.project.openCount, 2)
        model.undo()
        XCTAssertEqual(model.projects.first?.openCount, 2)
        model.flushPersistence()
        XCTAssertEqual(AppModel(storageURL: url).recentProjects.first?.project.lastOpenedAt, Date(timeIntervalSince1970: 200))
        model.recordProjectOpened(UUID())
        XCTAssertEqual(model.projects.count, 1)
    }

    func testLaunchScriptPreservesQuotedPathsEnvironmentAndCommand() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("workflow ' $(literal) " + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let project = Project(folderURL: dir)
        let configuration = LaunchConfiguration(name: "Dev", command: "printf '%s\\n%s' \"$PWD\" \"$CANVAS_VALUE\" > result.txt", workingDirectory: ".", environment: ["CANVAS_VALUE": "hello ' $(touch injected)\nworld"])
        let script = dir.appendingPathComponent("run.command")
        try ProjectLauncher.launchScript(project: project, configuration: configuration).write(to: script, atomically: true, encoding: .utf8)
        let result = try ProcessRunner.run(executable: "/bin/zsh", arguments: [script.path])
        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("result.txt")), dir.path + "\nhello ' $(touch injected)\nworld")
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("injected").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: script.path))
        var invalid = configuration
        invalid.environment = ["BAD;KEY": "value"]
        XCTAssertThrowsError(try ProjectLauncher.launchScript(project: project, configuration: invalid))
        invalid.environment = ["BAD\n": "value"]
        XCTAssertThrowsError(try ProjectLauncher.launchScript(project: project, configuration: invalid))
        invalid = configuration; invalid.workingDirectory = "missing"
        XCTAssertThrowsError(try ProjectLauncher.launchScript(project: project, configuration: invalid))
    }

    func testLegacyProjectsDecodeAndInvalidConfigurationsAreRejected() throws {
        let project = Project(folderURL: URL(fileURLWithPath: "/tmp"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(project)) as? [String: Any])
        for key in ["tags", "launchConfigurations", "lastOpenedAt", "openCount"] { json.removeValue(forKey: key) }
        let legacy = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(legacy.tags.isEmpty)
        XCTAssertTrue(legacy.launchConfigurations.isEmpty)
        XCTAssertEqual(legacy.openCount, 0)
        var invalid = project
        invalid.launchConfigurations = [LaunchConfiguration(name: "", command: "echo ok")]
        let data = ProjectCanvasData(projects: [invalid], groups: [], selectedGroupID: nil)
        XCTAssertThrowsError(try CanvasStorage.decode(JSONEncoder().encode(data)))
    }

    func testLaunchSettingsTakePrecedenceOverLoginProfile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "cd /\nexport CANVAS_VALUE=profile\n".write(to: dir.appendingPathComponent(".zprofile"), atomically: true, encoding: .utf8)
        let script = dir.appendingPathComponent("Launch.command")
        let config = LaunchConfiguration(name: "Dev", command: "printf '%s:%s' \"$PWD\" \"$CANVAS_VALUE\"", environment: ["CANVAS_VALUE": "configured"])
        try ProjectLauncher.launchScript(project: Project(folderURL: dir), configuration: config).write(to: script, atomically: true, encoding: .utf8)
        let result = try ProcessRunner.run(executable: "/usr/bin/env", arguments: ["ZDOTDIR=" + dir.path, "/bin/zsh", script.path])
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output, dir.path + ":configured")
    }

    @MainActor func testRecentAndFrequentRankingExcludeUnopenedProjectsAndPreserveBackups() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let folders = ["One", "Two", "Unused"].map { dir.appendingPathComponent($0) }
        for folder in folders { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        let url = dir.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url)
        defer { model.flushPersistence() }
        model.addProjects(folderURLs: folders, to: try XCTUnwrap(model.selectedGroupID))
        let first = model.projects[0].id, second = model.projects[1].id
        model.flushPersistence()
        let backup = try Data(contentsOf: url.appendingPathExtension("backup1"))
        model.recordProjectOpened(first, at: Date(timeIntervalSince1970: 100))
        model.recordProjectOpened(first, at: Date(timeIntervalSince1970: 200))
        model.recordProjectOpened(second, at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(model.recentProjects.map(\.project.id), [second, first])
        XCTAssertEqual(model.frequentProjects.map(\.project.id), [first, second])
        model.flushPersistence()
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup1")), backup)
    }

    @MainActor func testFilteringDropsDanglingRelationshipsAndPartialRegionsWithoutEditingOriginal() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(storageURL: dir.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        let secondFolder = dir.appendingPathComponent("Two")
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        model.addProjects(folderURLs: [dir, secondFolder], to: try XCTUnwrap(model.selectedGroupID))
        let group = try XCTUnwrap(model.selectedGroup)
        let first = group.cards[0], second = group.cards[1]
        model.connectCards(first.id, second.id, in: group.id)
        model.addRegion(name: "Both", color: .blue, cardIDs: [first.id, second.id], in: group.id)
        XCTAssertTrue(model.saveProjectWorkflow(try XCTUnwrap(first.projectID), tags: ["API"], configurations: []))
        let original = try XCTUnwrap(model.selectedGroup)
        let filtered = model.filteredGroup(original, tag: "API")
        XCTAssertEqual(filtered.cards.map(\.id), [first.id])
        XCTAssertTrue(filtered.connections.isEmpty)
        XCTAssertEqual(filtered.regions.first?.cardIDs, [first.id])
        XCTAssertEqual(model.selectedGroup, original)
    }

    @MainActor func testWorkflowImportUndoAndInvalidSaveAreAtomic() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(storageURL: dir.appendingPathComponent("source.json"))
        defer { model.flushPersistence() }
        model.addProject(folderURL: dir)
        let id = try XCTUnwrap(model.projects.first?.id)
        let config = LaunchConfiguration(name: "Dev", command: "echo ok", workingDirectory: "sub", environment: ["MODE": "dev"])
        XCTAssertTrue(model.saveProjectWorkflow(id, tags: ["API"], configurations: [config]))
        let saved = model.projects
        XCTAssertFalse(model.saveProjectDetails(id, notes: "changed", links: [], tags: ["new"], configurations: [LaunchConfiguration(name: "", command: "")]))
        XCTAssertEqual(model.projects, saved)
        let exported = dir.appendingPathComponent("export.json")
        model.exportGroup(try XCTUnwrap(model.selectedGroupID), to: exported)
        model.flushPersistence()
        let imported = AppModel(storageURL: dir.appendingPathComponent("target.json"))
        imported.importGroups(from: exported, pathFrom: "", pathTo: "")
        XCTAssertEqual(imported.projects.first?.tags, ["API"])
        XCTAssertEqual(imported.projects.first?.launchConfigurations, [config])
        model.undo()
        XCTAssertTrue(model.projects[0].tags.isEmpty)
        XCTAssertTrue(model.projects[0].launchConfigurations.isEmpty)
        model.redo()
        XCTAssertEqual(model.projects, saved)
    }

    @MainActor func testFailedOpenDoesNotRecordUsage() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let model = AppModel(storageURL: dir.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        let folder = dir.appendingPathComponent("missing")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        model.addProject(folderURL: folder)
        let project = try XCTUnwrap(model.projects.first)
        try FileManager.default.removeItem(at: folder)
        model.openProject(project)
        for _ in 0..<100 where model.alertMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.alertMessage)
        XCTAssertTrue(model.recentProjects.isEmpty)
        XCTAssertEqual(model.projects.first?.openCount, 0)
        model.alertMessage = nil
        model.runProject(project, configuration: LaunchConfiguration(name: "Dev", command: "echo ok"))
        for _ in 0..<100 where model.alertMessage == nil { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(model.alertMessage)
        XCTAssertEqual(model.projects.first?.openCount, 0)
    }
}
