import XCTest
@testable import ProjectCanvas

final class DesktopAlignmentTests: XCTestCase {
    func testGuidesMapOntoDesktopCardEdges() throws {
        let a = ProjectCard(clipboard: .note("a"), x: 100, y: 100)
        let b = ProjectCard(clipboard: .note("b"), x: 500, y: 400)
        let screen = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let layout = DesktopSceneLayout(cards: [a, b], screenFrame: screen, visibleFrame: screen.insetBy(dx: 100, dy: 100))
        // A vertical guide on card a's left edge, spanning both cards.
        let guide = CanvasAlignment.Guide(start: CGPoint(x: 100, y: 100), end: CGPoint(x: 100, y: 500))
        let local = try XCTUnwrap(layout.localGuides([guide]).first)
        let frameA = try XCTUnwrap(layout.cardFrames[a.id])
        XCTAssertEqual(local.start.x, frameA.minX - screen.minX, accuracy: 0.001)
        XCTAssertEqual(local.end.x, local.start.x, accuracy: 0.001)
        // The blur panel is flipped: canvas y grows downward on screen.
        XCTAssertEqual(local.start.y, screen.maxY - frameA.maxY, accuracy: 0.001)
        XCTAssertGreaterThan(local.end.y, local.start.y)
    }

    func testDesktopDragSnapsWithinSixScreenPoints() {
        let still = ProjectCard(clipboard: .note("still"), x: 100, y: 100)
        let moving = ProjectCard(clipboard: .note("moving"), x: 100, y: 400)
        // At scale 0.5, 6 screen points are 12 canvas points: 10 snaps, 20 does not.
        let near = CanvasAlignment.resolve(cards: [still, moving], movingIDs: [moving.id], proposed: CGSize(width: 10, height: 0), zoom: 0.5)
        XCTAssertEqual(near.offset.width, 0, accuracy: 0.001)
        XCTAssertFalse(near.guides.isEmpty)
        let far = CanvasAlignment.resolve(cards: [still, moving], movingIDs: [moving.id], proposed: CGSize(width: 20, height: 0), zoom: 0.5)
        XCTAssertEqual(far.offset.width, 20, accuracy: 0.001)
        let off = CanvasAlignment.resolve(cards: [still, moving], movingIDs: [moving.id], proposed: CGSize(width: 10, height: 0), zoom: 0.5, enabled: false)
        XCTAssertEqual(off.offset.width, 10, accuracy: 0.001)
    }

    func testDesktopDragMayCrossTheCanvasOrigin() {
        let card = ProjectCard(clipboard: .note("edge"), x: 30, y: 30)
        let canvas = CanvasAlignment.resolve(cards: [card], movingIDs: [card.id], proposed: CGSize(width: -100, height: 0), zoom: 1)
        XCTAssertEqual(canvas.offset.width, -10, accuracy: 0.001)
        let desktop = CanvasAlignment.resolve(cards: [card], movingIDs: [card.id], proposed: CGSize(width: -100, height: 0),
                                              zoom: 1, clampsToOrigin: false)
        XCTAssertEqual(desktop.offset.width, -100, accuracy: 0.001)
    }
}
