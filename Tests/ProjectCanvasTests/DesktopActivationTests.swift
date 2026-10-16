import XCTest
@testable import ProjectCanvas

final class DesktopActivationTests: XCTestCase {
    @MainActor func testSwitchingApplicationsDismissesOnlyForegroundOverlay() throws {
        let name = "DesktopActivationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            preferences.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        preferences.set(true, forKey: "desktopDisplayEnabled")
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"), preferences: preferences)
        model.restoreDesktopDisplayIfNeeded()
        let controller = try XCTUnwrap(model.desktopDisplayController)
        let ownProcess = ProcessInfo.processInfo.processIdentifier
        model.setDesktopDisplayMode(.foregroundOverlay)
        controller.applicationActivated(processID: ownProcess)
        XCTAssertTrue(model.isDesktopDisplayOn)
        controller.applicationActivated(processID: ownProcess + 1)
        XCTAssertFalse(model.isDesktopDisplayOn)
        XCTAssertFalse(preferences.bool(forKey: "desktopDisplayEnabled"))
        controller.applicationActivated(processID: ownProcess + 1)
        XCTAssertFalse(model.isDesktopDisplayOn)
        for mode in DesktopDisplayMode.allCases where mode != .foregroundOverlay {
            model.setDesktopDisplayMode(mode)
            model.toggleDesktopDisplay()
            controller.applicationActivated(processID: ownProcess + 1)
            XCTAssertTrue(model.isDesktopDisplayOn)
        }
    }
}
