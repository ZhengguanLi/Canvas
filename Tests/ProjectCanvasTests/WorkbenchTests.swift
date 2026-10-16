import XCTest
@testable import ProjectCanvas

final class WorkbenchTests: XCTestCase {
    private func fixture() throws -> (URL, ProjectCanvasData) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let projects = [Project(folderURL: dir), Project(folderURL: dir.appendingPathComponent("API")), Project(folderURL: dir.appendingPathComponent("DB"))]
        let cards = projects.enumerated().map { ProjectCard(projectID: $0.element.id, x: 71.25 + Double($0.offset) * 45, y: 352.75 - Double($0.offset) * 80) }
        let edges = [ProjectConnection(fromCardID: cards[0].id, toCardID: cards[1].id), ProjectConnection(fromCardID: cards[1].id, toCardID: cards[0].id), ProjectConnection(fromCardID: cards[1].id, toCardID: cards[2].id)]
        let group = ProjectGroup(name: "Services", cards: cards, connections: edges)
        return (dir.appendingPathComponent("canvas.json"), ProjectCanvasData(projects: projects, groups: [group], selectedGroupID: group.id))
    }

    @MainActor func testLayoutPreviewPreservesDiskAndUndoRestoresExactCoordinates() throws {
        let (url, data) = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try CanvasStorage(url: url).save(data)
        let model = AppModel(storageURL: url)
        let before = try Data(contentsOf: url)
        let preview = try XCTUnwrap(model.makeLayoutPreview(in: data.groups[0].id, mode: .relationships))
        XCTAssertEqual(model.groups, data.groups)
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(preview.proposed.cards, model.makeLayoutPreview(in: data.groups[0].id, mode: .relationships)?.proposed.cards)
        XCTAssertGreaterThan(preview.proposed.cards[2].x, preview.proposed.cards[1].x)
        XCTAssertTrue(model.applyLayout(preview))
        model.undo()
        XCTAssertEqual(model.groups, data.groups)
        XCTAssertFalse(model.canUndo)
        model.moveCard(data.groups[0].cards[0].id, to: CGPoint(x: 600, y: 550), in: data.groups[0].id)
        let edited = model.groups
        XCTAssertFalse(model.applyLayout(preview))
        XCTAssertEqual(model.groups, edited)
    }

    @MainActor func testRegionsDetailsSearchAndImport() throws {
        let (url, data) = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try CanvasStorage(url: url).save(data)
        let model = AppModel(storageURL: url), group = data.groups[0]
        let members = Set(group.cards.prefix(2).map(\.id))
        model.addRegion(name: "Backend", color: .blue, cardIDs: members, in: group.id)
        let region = try XCTUnwrap(model.selectedGroup?.regions.first)
        model.moveRegion(region.id, by: CGSize(width: 30, height: 40), in: group.id)
        XCTAssertEqual(model.selectedGroup?.cards[0].x, group.cards[0].x + 30)
        model.removeRegion(region.id, in: group.id)
        XCTAssertEqual(model.selectedGroup?.cards.count, 3)
        model.undo()
        XCTAssertTrue(model.saveProjectDetails(data.projects[0].id, notes: "notes", links: [ProjectLink(name: "Docs", address: "https://example.com/docs")]))
        XCTAssertFalse(model.saveProjectDetails(data.projects[0].id, notes: "bad", links: [ProjectLink(name: "Bad", address: "javascript:alert(1)")]))
        XCTAssertEqual(model.projects[0].notes, "notes")
        model.undo(); XCTAssertNil(model.projects[0].notes)
        XCTAssertEqual(model.searchProjects("api").count, 1)
        let exported = url.deletingLastPathComponent().appendingPathComponent("export.json")
        model.exportGroup(group.id, to: exported)
        model.importGroups(from: exported, pathFrom: "", pathTo: "")
        let imported = try XCTUnwrap(model.selectedGroup)
        XCTAssertEqual(imported.regions.count, 1)
        XCTAssertEqual(imported.regions[0].cardIDs.count, 2)
        XCTAssertTrue(Set(imported.cards.map(\.id)).isSuperset(of: imported.regions[0].cardIDs))
        XCTAssertTrue(members.isDisjoint(with: imported.regions[0].cardIDs))
    }

    @MainActor func testGridCancelRegionEditingAndCrossGroupSearch() throws {
        let (url, data) = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var initial = data
        var second = data.groups[0]; second.id = UUID(); second.name = "Second"
        second.cards = second.cards.map { var card = $0; card.id = UUID(); card.customName = "Special Alias"; return card }; second.connections = []
        initial.groups.append(second)
        try CanvasStorage(url: url).save(initial)
        let model = AppModel(storageURL: url), group = initial.groups[0]
        model.autoLayoutCards(in: group.id)
        let before = try Data(contentsOf: url)
        XCTAssertNotNil(model.layoutPreview)
        model.layoutPreview = nil
        XCTAssertEqual(try Data(contentsOf: url), before)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.searchProjects("Special Alias").count, 3)
        XCTAssertEqual(model.searchProjects("api").count, 2)
        let result = try XCTUnwrap(model.searchProjects("Special Alias").first)
        model.locate(result)
        XCTAssertEqual(model.selectedGroupID, second.id)
        XCTAssertEqual(model.locateRequest?.cardID, result.card.id)
        let firstRequest = model.locateRequest
        model.locate(result); XCTAssertNotEqual(firstRequest, model.locateRequest)
        model.addRegion(name: "Old", color: .blue, cardIDs: [group.cards[0].id], in: group.id)
        let region = try XCTUnwrap(model.groups[0].regions.first)
        model.updateRegion(region.id, name: "New", color: .green, in: group.id)
        XCTAssertEqual(model.groups[0].regions.first?.name, "New")
        model.undo(); XCTAssertEqual(model.groups[0].regions.first?.name, "Old")
        model.removeCard(group.cards[0].id, from: group.id)
        XCTAssertTrue(model.groups[0].regions.isEmpty)
        XCTAssertNoThrow(try CanvasStorage(url: url).load())
        model.undo(); XCTAssertEqual(model.groups[0].regions.first, region)
    }

    func testLegacyRegionsAndInvalidMembership() throws {
        let (url, data) = try fixture(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as? [String: Any])
        var groups = try XCTUnwrap(object["groups"] as? [[String: Any]])
        groups[0].removeValue(forKey: "regions"); groups[0].removeValue(forKey: "storedRegions"); object["groups"] = groups
        XCTAssertTrue(try CanvasStorage.decode(JSONSerialization.data(withJSONObject: object)).groups[0].regions.isEmpty)
        var invalid = data
        invalid.groups[0].regions = [ProjectRegion(name: "Invalid", color: .blue, cardIDs: [UUID()])]
        XCTAssertThrowsError(try CanvasStorage.decode(JSONEncoder().encode(invalid)))
    }
}
