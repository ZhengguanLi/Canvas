import XCTest
@testable import ProjectCanvas

final class CanvasMinimapTests: XCTestCase {
    func testOffsetCentersPointAndClampsToScrollableRange() {
        let world = CGSize(width: 2000, height: 1500), viewport = CGSize(width: 800, height: 600)
        XCTAssertEqual(CanvasMinimap.offset(centeredOn: CGPoint(x: 1000, y: 750), zoom: 1, viewport: viewport, world: world),
                       CGPoint(x: 600, y: 450))
        XCTAssertEqual(CanvasMinimap.offset(centeredOn: .zero, zoom: 1, viewport: viewport, world: world), .zero)
        XCTAssertEqual(CanvasMinimap.offset(centeredOn: CGPoint(x: 5000, y: 5000), zoom: 1, viewport: viewport, world: world),
                       CGPoint(x: 1200, y: 900))
        XCTAssertEqual(CanvasMinimap.offset(centeredOn: CGPoint(x: 1000, y: 750), zoom: 2, viewport: viewport, world: world),
                       CGPoint(x: 1600, y: 1200))
    }

    func testOnlyUsefulWhenCanvasOverflowsViewport() {
        XCTAssertFalse(CanvasMinimap.isUseful(extent: CGSize(width: 1200, height: 300), clotheslineHeight: 200, zoom: 1, viewport: CGSize(width: 1300, height: 800)))
        XCTAssertTrue(CanvasMinimap.isUseful(extent: CGSize(width: 1200, height: 900), clotheslineHeight: 200, zoom: 1, viewport: CGSize(width: 1300, height: 800)))
        XCTAssertTrue(CanvasMinimap.isUseful(extent: CGSize(width: 1200, height: 300), clotheslineHeight: 200, zoom: 2, viewport: CGSize(width: 1300, height: 800)))
    }
}
