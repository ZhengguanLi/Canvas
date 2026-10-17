import AppKit
import SwiftUI
import XCTest
@testable import ProjectCanvas

final class ClipboardClotheslineTests: XCTestCase {
    @MainActor func testClotheslineRendersHangingCards() throws {
        _ = NSApplication.shared
        let ids = (0..<8).map { _ in UUID() }
        let view = ClipboardClothesline {
            ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                Text("Clipboard note \(index + 1)\nClick to copy")
                    .font(.system(size: 14)).frame(width: 180, height: 90).padding(8)
                    .hangingClipboardCard(id: id)
            }
        }.frame(height: 150).padding(16).background(Color(nsColor: .textBackgroundColor))
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 760, height: 182)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // The first card's clip hangs at its horizontal centre, just below the rope.
        XCTAssertNotEqual(try XCTUnwrap(bitmap.color(atPoint: CGPoint(x: 126, y: 38), in: host.bounds)),
                          try XCTUnwrap(bitmap.color(atPoint: CGPoint(x: 50, y: 10), in: host.bounds)))
        if let path = ProcessInfo.processInfo.environment["PROJECTCANVAS_CLOTHESLINE_PREVIEW"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
    }

    func testRopeHasSymmetricSagAndStableAnchors() {
        let width = 1000.0
        XCTAssertEqual(ClipboardClotheslineGeometry.ropeY(at: 0, width: width), 13)
        XCTAssertEqual(ClipboardClotheslineGeometry.ropeY(at: width, width: width), 13)
        XCTAssertGreaterThan(ClipboardClotheslineGeometry.ropeY(at: width / 2, width: width), 13)
        XCTAssertEqual(ClipboardClotheslineGeometry.ropeY(at: 200, width: width),
                       ClipboardClotheslineGeometry.ropeY(at: 800, width: width), accuracy: 0.001)
        XCTAssertEqual(ClipboardClotheslineGeometry.ropeY(at: 10, width: 0), 13)
    }

    func testHangingRowsReserveRoomForClipsAndShadowsAtEverySize() {
        for scale in [1.0, 1.25, 2.0] {
            let appearance = ClipboardAppearance(imageScale: scale, textSize: 24)
            XCTAssertGreaterThanOrEqual(appearance.imageRowHeight, 62 * scale + 8 + 25 + 12)
            XCTAssertGreaterThanOrEqual(appearance.textRowHeight, 54 * 24 / 11 + 16 + 25 + 12)
        }
        let id = UUID()
        XCTAssertEqual(ClipboardClotheslineGeometry.tilt(for: id), ClipboardClotheslineGeometry.tilt(for: id))
        XCTAssertLessThanOrEqual(abs(ClipboardClotheslineGeometry.tilt(for: id)), 0.8)
    }
}
