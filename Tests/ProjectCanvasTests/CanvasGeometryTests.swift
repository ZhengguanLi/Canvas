import XCTest
@testable import ProjectCanvas

final class CanvasGeometryTests: XCTestCase {
    func testRegionHeaderRemainsAccessibleNearTopWithoutMovingCards() {
        let cards = CGRect(x: 20, y: 20, width: 400, height: 160)
        let region = CanvasGeometry.regionPresentation(around: cards)
        XCTAssertGreaterThanOrEqual(region.frame.minY, 0)
        XCTAssertGreaterThan(region.header.y - 16, cards.maxY)
        XCTAssertTrue(region.frame.contains(region.header))
        let regular = CanvasGeometry.regionPresentation(around: cards.offsetBy(dx: 0, dy: 100))
        XCTAssertLessThan(regular.header.y + 16, 120)
    }

    func testExtentIncludesCardsBeyondOriginalBoard() {
        let card = ProjectCard(projectID: UUID(), x: 4000, y: 2500)
        let size = CanvasGeometry.extent(cards: [card])
        XCTAssertGreaterThanOrEqual(size.width, 4330)
        XCTAssertGreaterThanOrEqual(size.height, 2720)
    }

    func testArrowsMeetVerticalCardEdge() {
        let end = CanvasGeometry.edgePoint(from: CGPoint(x: 105, y: 50), to: CGPoint(x: 105, y: 350))
        XCTAssertEqual(end.x, 105, accuracy: 0.01)
        XCTAssertEqual(end.y, 300, accuracy: 0.01)
    }

    func testGroupMovementPreservesSpacingAtOrigin() {
        let first = ProjectCard(projectID: UUID(), x: 20, y: 50)
        let second = ProjectCard(projectID: UUID(), x: 200, y: 100)
        let offset = CanvasGeometry.clampedOffset(CGSize(width: -100, height: -100), cards: [first, second])
        XCTAssertEqual(offset.width, 0)
        XCTAssertEqual(offset.height, -30)
    }
}
