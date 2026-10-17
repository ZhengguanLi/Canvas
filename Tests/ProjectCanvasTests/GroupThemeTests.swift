import XCTest
@testable import ProjectCanvas

final class GroupThemeTests: XCTestCase {
    @MainActor func testGroupThemePersistsAndClears() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "GroupThemeTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url, preferences: preferences)
        let groupID = try XCTUnwrap(model.selectedGroupID)
        let theme = GroupCanvasTheme(colorHex: "#D8B68C", opacity: 0.3)
        model.setCanvasTheme(theme, for: groupID)
        model.flushPersistence()
        XCTAssertEqual(AppModel(storageURL: url, preferences: preferences).groups.first { $0.id == groupID }?.canvasTheme, theme)
        model.setCanvasTheme(nil, for: groupID)
        model.flushPersistence()
        XCTAssertNil(AppModel(storageURL: url, preferences: preferences).groups.first { $0.id == groupID }?.canvasTheme)
    }

    func testLegacyGroupWithoutThemeDecodes() throws {
        var group = ProjectGroup(name: "Legacy")
        group.canvasTheme = nil
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(group)) as? [String: Any])
        json.removeValue(forKey: "canvasTheme")
        let decoded = try JSONDecoder().decode(ProjectGroup.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.canvasTheme)
        XCTAssertEqual(decoded.name, "Legacy")
    }
}
