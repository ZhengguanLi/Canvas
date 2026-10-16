import AppKit
import XCTest
@testable import ProjectCanvas

final class DesktopAppearanceTests: XCTestCase {
    func testCanvasAndDesktopUseTheSameTintAndReset() throws {
        let name = "SharedBackgroundTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let warm = BackgroundTint(color: try XCTUnwrap(BackgroundTintColor(hex: "#D8B68C")), opacity: 0.6)
        warm.saveShared(to: preferences)
        XCTAssertEqual(DesktopAppearance.load(from: preferences).tintColor, warm.color)
        XCTAssertEqual(DesktopAppearance.load(from: preferences).tintOpacity, 0.6)
        let desktop = DesktopAppearance(tintColor: try XCTUnwrap(BackgroundTintColor(hex: "#6B9BD2")), tintOpacity: 0.3)
        desktop.save(to: preferences)
        XCTAssertEqual(BackgroundTint.loadShared(from: preferences), BackgroundTint(color: desktop.tintColor, opacity: 0.3))
        DesktopAppearance().save(to: preferences)
        XCTAssertEqual(BackgroundTint.loadShared(from: preferences).opacity, 0)
    }

    func testMigrationPreservesCanvasChoiceAndDoesNotOverwriteNewSettings() throws {
        let name = "TintMigrationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let warm = BackgroundTint(color: try XCTUnwrap(BackgroundTintColor(hex: "#D8B68C")), opacity: 0.435)
        warm.save(to: preferences, prefix: "canvas")
        BackgroundTint(opacity: 0.2).save(to: preferences, prefix: "desktop")
        BackgroundTint.migrateLegacyPreferences(from: preferences)
        XCTAssertEqual(BackgroundTint.loadShared(from: preferences), warm)
        let blue = BackgroundTint(opacity: 0.5)
        blue.saveShared(to: preferences)
        BackgroundTint.migrateLegacyPreferences(from: preferences)
        XCTAssertEqual(BackgroundTint.loadShared(from: preferences), blue)
        XCTAssertEqual(BackgroundTintColor(red: .nan, green: 2, blue: -1).hex, "#00FF00")
    }

    func testMigrationKeepsDesktopTintWhenCanvasWasNeverConfigured() throws {
        let name = "DesktopTintMigrationTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        let legacy = BackgroundTint(opacity: 0.4)
        legacy.save(to: preferences, prefix: "desktop")
        BackgroundTint.migrateLegacyPreferences(from: preferences)
        XCTAssertEqual(BackgroundTint.loadShared(from: preferences), legacy)
    }

    func testTintPersistenceDefaultsAndInvalidPreferences() throws {
        let name = "DesktopTintTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        XCTAssertEqual(DesktopAppearance.load(from: preferences).tintOpacity, 0)
        let blue = try XCTUnwrap(BackgroundTintColor(hex: "#6B9BD2"))
        let appearance = DesktopAppearance(tintColor: blue, tintOpacity: 0.35)
        appearance.save(to: preferences)
        XCTAssertEqual(DesktopAppearance.load(from: preferences), appearance)
        XCTAssertEqual(blue.hex, "#6B9BD2")
        preferences.set("not a color", forKey: "backgroundTintColor")
        preferences.set(Double.infinity, forKey: "backgroundTintOpacity")
        let recovered = DesktopAppearance.load(from: preferences)
        XCTAssertEqual(recovered.tintColor, BackgroundTintColor.default)
        XCTAssertEqual(recovered.tintOpacity, 0)
        XCTAssertEqual(DesktopAppearance(tintOpacity: -1).tintOpacity, 0)
        XCTAssertEqual(DesktopAppearance(tintOpacity: 3).tintOpacity, 0.8)
        XCTAssertNil(BackgroundTintColor(hex: "#12345G"))
        XCTAssertNil(BackgroundTintColor(hex: "#FFF"))
        DesktopAppearance().save(to: preferences)
        XCTAssertEqual(DesktopAppearance.load(from: preferences).tintOpacity, 0)
    }

    @MainActor func testTintSitsAboveBlurBelowDimmingAndConnections() throws {
        let view = DesktopBackgroundBlurView(frame: CGRect(x: 0, y: 0, width: 500, height: 300))
        let color = try XCTUnwrap(BackgroundTintColor(hex: "#4080C0"))
        view.update(appearance: DesktopAppearance(blur: 0.6, dimming: 0.2, tintColor: color, tintOpacity: 0.4))
        XCTAssertTrue(view.subviews[0] === view.effect)
        XCTAssertTrue(view.subviews[1] === view.tint)
        XCTAssertTrue(view.subviews.last === view.connections)
        XCTAssertEqual(view.effect.alphaValue, 0.6)
        let tint = try XCTUnwrap(view.tint.layer?.backgroundColor).components
        XCTAssertEqual(try XCTUnwrap(tint?[0]), 64.0 / 255, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(tint?[3]), 0.4, accuracy: 0.001)
        view.update(appearance: DesktopAppearance())
        XCTAssertEqual(try XCTUnwrap(view.tint.layer?.backgroundColor).alpha, 0)
        XCTAssertTrue(view.hitTest(CGPoint(x: 20, y: 20)) === view)
    }

    func testAppearanceDefaultsPersistenceAndBounds() throws {
        let name = "DesktopAppearanceTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        XCTAssertEqual(DesktopAppearance.load(from: preferences), DesktopAppearance())
        let appearance = DesktopAppearance(blur: 0.4, dimming: 0.3, cardScale: 1.2, showsLabels: false)
        appearance.save(to: preferences)
        XCTAssertEqual(DesktopAppearance.load(from: preferences), appearance)
        XCTAssertEqual(DesktopAppearance(blur: -1, dimming: 2, cardScale: 9).blur, 0)
        XCTAssertEqual(DesktopAppearance(blur: -1, dimming: 2, cardScale: 9).dimming, 0.8)
        XCTAssertEqual(DesktopAppearance(blur: -1, dimming: 2, cardScale: 9).cardScale, 1.5)
    }

    func testRequestedScaleKeepsConnectionsOnCardEdges() throws {
        let a = ProjectCard(projectID: UUID(), x: 0, y: 0)
        let b = ProjectCard(projectID: UUID(), x: 400, y: 0)
        let group = ProjectGroup(name: "test", cards: [a, b], connections: [ProjectConnection(fromCardID: a.id, toCardID: b.id)], showsConnections: true)
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1200)
        let layout = DesktopSceneLayout(cards: group.cards, screenFrame: screen, visibleFrame: screen, requestedScale: 1.5)
        XCTAssertEqual(layout.scale, 1.5)
        let edge = try XCTUnwrap(layout.connections(in: group).first)
        XCTAssertEqual(edge.start.x, try XCTUnwrap(layout.cardFrames[a.id]).maxX, accuracy: 0.01)
        XCTAssertEqual(edge.end.x, try XCTUnwrap(layout.cardFrames[b.id]).minX, accuracy: 0.01)
    }
}
