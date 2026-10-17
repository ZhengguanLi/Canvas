import XCTest
@testable import ProjectCanvas

final class CardScaleTests: XCTestCase {
    func testCardScaleIsClampedToSliderRange() {
        XCTAssertEqual(CanvasGeometry.clampedCardScale(1.4), 1.4)
        XCTAssertEqual(CanvasGeometry.clampedCardScale(0.5), 1)
        XCTAssertEqual(CanvasGeometry.clampedCardScale(5), 2)
        XCTAssertEqual(CanvasGeometry.clampedCardScale(.nan), 1)
    }

    func testScaledCardKeepsItsCentre() {
        let frame = CanvasGeometry.cardFrame(x: 100, y: 200, scale: 2)
        XCTAssertEqual(frame.midX, 100 + 105)
        XCTAssertEqual(frame.midY, 200 + 50)
        XCTAssertEqual(frame.size, CGSize(width: 420, height: 200))
        XCTAssertEqual(CanvasGeometry.cardFrame(x: 10, y: 20, scale: 1), CGRect(x: 10, y: 20, width: 210, height: 100))
    }

    func testExtentAndConnectionsGrowWithCardScale() {
        let card = ProjectCard(clipboard: .note(""), x: 2000, y: 1000)
        XCTAssertEqual(CanvasGeometry.extent(cards: [card]), CGSize(width: 2330, height: 1220))
        XCTAssertEqual(CanvasGeometry.extent(cards: [card], cardScale: 2), CGSize(width: 2435, height: 1270))
        let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 1000, y: 0)
        XCTAssertEqual(CanvasGeometry.edgePoint(from: a, to: b).x, 895, accuracy: 0.001)
        XCTAssertEqual(CanvasGeometry.edgePoint(from: a, to: b, scale: 2).x, 790, accuracy: 0.001)
    }
}
