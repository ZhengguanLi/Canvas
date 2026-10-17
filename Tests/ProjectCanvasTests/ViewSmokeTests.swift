import AppKit
import SwiftUI
import XCTest
@testable import ProjectCanvas

final class ViewSmokeTests: XCTestCase {
    @MainActor func testCanvasBackgroundRendersSavedTint() throws {
        _ = NSApplication.shared
        let name = "CanvasBackgroundTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { preferences.removePersistentDomain(forName: name) }
        BackgroundTint(color: try XCTUnwrap(BackgroundTintColor(hex: "#0000FF")), opacity: 0.8)
            .saveShared(to: preferences)
        let host = NSHostingView(rootView: CanvasBackgroundView().defaultAppStorage(preferences).environment(\.colorScheme, .light))
        host.appearance = NSAppearance(named: .aqua)
        host.frame = CGRect(x: 0, y: 0, width: 100, height: 100)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let pixel = try XCTUnwrap(bitmap.color(atPoint: CGPoint(x: 50, y: 50), in: host.bounds)?.usingColorSpace(.sRGB))
        XCTAssertEqual(pixel.blueComponent, 1, accuracy: 0.03)
        // Color-managed AppKit captures can shift components; the saved tint must still dominate.
        XCTAssertGreaterThan(pixel.blueComponent - max(pixel.redComponent, pixel.greenComponent), 0.5)
    }

    @MainActor func testCanvasRendersAtSmallViewportAndPreservesNativeScrollOffset() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        model.addProjects(folderURLs: [directory], to: model.selectedGroupID!)
        let group = model.selectedGroup!
        model.setCardColor(.blue, ids: [group.cards[0].id], in: group.id)
        let board = CanvasBoard(model: model, group: model.selectedGroup!, zoom: 1,
                                isEditing: true, snapToGrid: true,
                                selectedCardIDs: .constant([group.cards[0].id]), selectedConnectionID: .constant(nil),
                                isConnecting: .constant(false), firstConnectionCardID: .constant(nil),
                                highlightDirection: 0, onOpenSettings: { _ in }, onRelocate: { _ in })
        let view = CanvasScrollView(size: CGSize(width: 1200, height: 800), offset: .constant(CGPoint(x: 100, y: 50))) { board }
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 500)
        host.layoutSubtreeIfNeeded()
        func findScroll(in view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll(in: $0) }.first
        }
        let scroll = try XCTUnwrap(findScroll(in: host))
        XCTAssertEqual(scroll.documentView?.frame.width, 1200)
        XCTAssertEqual(scroll.documentView?.frame.height, 800)
        XCTAssertEqual(scroll.contentView.bounds.origin.x, 100, accuracy: 1)
        XCTAssertEqual(scroll.contentView.bounds.origin.y, 50, accuracy: 1)
        XCTAssertNotNil(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    }
    @MainActor func testCanvasSelectionSurfaceCoversLargeViewportAtEveryZoom() throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        model.addProject(folderURL: directory)
        let group = try XCTUnwrap(model.selectedGroup)
        let viewport = CGSize(width: 3000, height: 1600)
        for zoom in [0.25, 1.0, 1.5] {
            let board = CanvasBoard(model: model, group: group, zoom: zoom, isEditing: true, snapToGrid: true,
                selectedCardIDs: .constant([]), selectedConnectionID: .constant(nil),
                isConnecting: .constant(false), firstConnectionCardID: .constant(nil), highlightDirection: 0,
                onOpenSettings: { _ in }, onRelocate: { _ in },
                minimumSize: CGSize(width: viewport.width / zoom, height: viewport.height / zoom))
            let host = NSHostingView(rootView: board)
            host.frame = CGRect(origin: .zero, size: viewport)
            host.layoutSubtreeIfNeeded()
            XCTAssertGreaterThanOrEqual(host.fittingSize.width, viewport.width - 1)
            XCTAssertGreaterThanOrEqual(host.fittingSize.height, viewport.height - 1)
        }
    }

    @MainActor func testImmediateTeardownCommitsPendingViewport() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        defer { model.flushPersistence() }
        let groupID = try XCTUnwrap(model.selectedGroupID)
        let committed = expectation(description: "pending viewport committed after teardown")
        let view = CanvasScrollView(size: CGSize(width: 1200, height: 800), offset: .constant(.zero), onViewportCommit: { position in
            model.updateViewport(CanvasViewport(zoom: 1, offsetX: position.x, offsetY: position.y), in: groupID)
            committed.fulfill()
        }) { Color.clear.frame(width: 1200, height: 800) }
        let coordinator = view.makeCoordinator()
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 700, height: 500))
        let content = NSHostingView(rootView: Color.clear.frame(width: 1200, height: 800))
        content.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        scroll.documentView = content
        scroll.contentView.scroll(to: CGPoint(x: 220, y: 130))
        coordinator.pendingPosition = scroll.contentView.bounds.origin
        model.addGroup()
        type(of: view).dismantleNSView(scroll, coordinator: coordinator)
        await fulfillment(of: [committed], timeout: 1)
        model.flushPersistence()
        let reopened = AppModel(storageURL: directory.appendingPathComponent("canvas.json"))
        XCTAssertEqual(reopened.groups.first(where: { $0.id == groupID })?.viewport?.offsetX, 220)
        XCTAssertEqual(reopened.groups.first(where: { $0.id == groupID })?.viewport?.offsetY, 130)
    }

}
