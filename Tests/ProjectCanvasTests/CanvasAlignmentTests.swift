import XCTest
@testable import ProjectCanvas

final class CanvasAlignmentTests: XCTestCase {
    func testEdgesSnapAndOverrideGridWithVisibleGuides() {
        let moving = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let target = ProjectCard(projectID: UUID(), x: 400, y: 400)
        for (proposed, expected) in [(CGSize(width: 295, height: 295), CGSize(width: 300, height: 300)),
                                     (CGSize(width: 85, height: 195), CGSize(width: 90, height: 200)),
                                     (CGSize(width: 505, height: 405), CGSize(width: 510, height: 400))] {
            let result = CanvasAlignment.resolve(cards: [moving, target], movingIDs: [moving.id], proposed: proposed,
                zoom: 1, gridAnchor: CGPoint(x: moving.x, y: moving.y))
            XCTAssertEqual(result.offset, expected)
            XCTAssertEqual(result.guides.count, 2)
            XCTAssertTrue(result.guides.allSatisfy { $0.start.x == $0.end.x || $0.start.y == $0.end.y })
        }
    }

    func testMultiSelectionUsesItsBoundsAndDoesNotSnapToItself() {
        let first = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let second = ProjectCard(projectID: UUID(), x: 350, y: 100)
        let target = ProjectCard(projectID: UUID(), x: 700, y: 400)
        let result = CanvasAlignment.resolve(cards: [first, second, target], movingIDs: [first.id, second.id],
            proposed: CGSize(width: 480, height: 0), zoom: 1)
        XCTAssertEqual(result.offset.width, 475)
        XCTAssertEqual(result.guides.first?.start.x, 805)
        let alone = CanvasAlignment.resolve(cards: [first, second], movingIDs: [first.id, second.id],
            proposed: CGSize(width: 3, height: 4), zoom: 1)
        XCTAssertEqual(alone.offset, CGSize(width: 3, height: 4))
        XCTAssertTrue(alone.guides.isEmpty)
    }

    func testSnapDistanceIsMeasuredOnScreenAndCanBeDisabled() {
        let moving = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let target = ProjectCard(projectID: UUID(), x: 400, y: 400)
        let proposed = CGSize(width: 292, height: 0)
        let zoomedOut = CanvasAlignment.resolve(cards: [moving, target], movingIDs: [moving.id], proposed: proposed, zoom: 0.5)
        XCTAssertEqual(zoomedOut.offset.width, 300)
        let zoomedIn = CanvasAlignment.resolve(cards: [moving, target], movingIDs: [moving.id], proposed: proposed, zoom: 2)
        XCTAssertEqual(zoomedIn.offset, proposed)
        XCTAssertTrue(zoomedIn.guides.isEmpty)
        let disabled = CanvasAlignment.resolve(cards: [moving, target], movingIDs: [moving.id], proposed: proposed,
            zoom: 0.5, enabled: false)
        XCTAssertEqual(disabled.offset, proposed)
        XCTAssertTrue(disabled.guides.isEmpty)
    }

    func testCanvasBoundaryDoesNotShowAnUnreachableAlignmentGuide() {
        let moving = ProjectCard(projectID: UUID(), x: 100, y: 100)
        let target = ProjectCard(projectID: UUID(), x: 17, y: 400)
        let result = CanvasAlignment.resolve(cards: [moving, target], movingIDs: [moving.id],
            proposed: CGSize(width: -77, height: 0), zoom: 1)
        XCTAssertEqual(moving.x + result.offset.width, 20)
        XCTAssertTrue(result.guides.isEmpty)
    }
}
