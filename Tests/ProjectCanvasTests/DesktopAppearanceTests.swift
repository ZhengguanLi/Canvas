import XCTest
@testable import ProjectCanvas

final class DesktopAppearanceTests: XCTestCase {
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
