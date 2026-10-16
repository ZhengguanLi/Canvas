import XCTest
@testable import ProjectCanvas

final class DesktopConnectionsTests: XCTestCase {
    func testWidelySeparatedCardsStillFitDisplay() throws {
        let cards = [ProjectCard(projectID: UUID(), x: 0, y: 0),
                     ProjectCard(projectID: UUID(), x: 200_000, y: 200_000)]
        let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let layout = DesktopSceneLayout(cards: cards, screenFrame: screen, visibleFrame: screen)
        for card in cards {
            let frame = try XCTUnwrap(layout.cardFrames[card.id])
            XCTAssertGreaterThanOrEqual(frame.minX, screen.minX - 0.01)
            XCTAssertGreaterThanOrEqual(frame.minY, screen.minY - 0.01)
            XCTAssertLessThanOrEqual(frame.maxX, screen.maxX + 0.01)
            XCTAssertLessThanOrEqual(frame.maxY, screen.maxY + 0.01)
        }
    }

    func testEdgesFollowScaledCardsOnOffsetMonitor() throws {
        let a = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let b = ProjectCard(projectID: UUID(), x: 1100, y: 100)
        let edge = ProjectConnection(fromCardID: a.id, toCardID: b.id)
        let group = ProjectGroup(name: "graph", cards: [a, b], connections: [edge], showsConnections: true)
        let screen = CGRect(x: -1200, y: -200, width: 800, height: 600)
        let layout = DesktopSceneLayout(cards: group.cards, screenFrame: screen, visibleFrame: screen.insetBy(dx: 24, dy: 24))
        let rendered = try XCTUnwrap(layout.connections(in: group).first)
        let first = try XCTUnwrap(layout.cardFrames[a.id])
        let second = try XCTUnwrap(layout.cardFrames[b.id])
        XCTAssertEqual(rendered.start.x, first.maxX - screen.minX, accuracy: 0.01)
        XCTAssertEqual(rendered.end.x, second.minX - screen.minX, accuracy: 0.01)
        XCTAssertEqual(rendered.start.y, screen.maxY - first.midY, accuracy: 0.01)
        XCTAssertEqual(rendered.end.y, screen.maxY - second.midY, accuracy: 0.01)
    }

    func testVisibilityAndReciprocalLabelsMatchGroup() throws {
        let a = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let b = ProjectCard(projectID: UUID(), x: 600, y: 100)
        var edge = ProjectConnection(fromCardID: a.id, toCardID: b.id)
        edge.kind = .call; edge.label = "API"
        var group = ProjectGroup(name: "graph", cards: [a, b], connections: [edge, ProjectConnection(fromCardID: b.id, toCardID: a.id)], showsConnections: false)
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let layout = DesktopSceneLayout(cards: group.cards, screenFrame: frame, visibleFrame: frame)
        XCTAssertTrue(layout.connections(in: group).isEmpty)
        group.showsConnections = true
        let edges = layout.connections(in: group)
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].label, "\(ConnectionKind.call.title) · API")
        XCTAssertNotEqual(edges[0].control.y, edges[1].control.y)
        group.cards.removeLast()
        XCTAssertTrue(layout.connections(in: group).isEmpty)
    }
}
