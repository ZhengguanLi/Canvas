import AppKit
import XCTest
@testable import ProjectCanvas

final class PerformanceRegressionTests: XCTestCase {
    private func fixture() throws -> (URL, ProjectCanvasData) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (directory.appendingPathComponent("canvas.json"), .empty)
    }

    func testViewportIsCoalescedAndFlushedWithoutRotatingBackups() throws {
        let (url, initial) = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let storage = CanvasStorage(url: url)
        try storage.save(initial)
        let writer = CanvasPersistence(storage: storage)
        var edited = initial
        edited.groups[0].name = "Edited"
        writer.save(edited, rotatingBackup: true)
        writer.flush()
        let backup = try Data(contentsOf: url.appendingPathExtension("backup1"))
        for x in 1...100 {
            edited.groups[0].viewport = CanvasViewport(zoom: 1, offsetX: Double(x), offsetY: 0)
            writer.scheduleViewport(edited)
        }
        writer.flush()
        XCTAssertEqual(try storage.load()?.groups[0].viewport?.offsetX, 100)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("backup1")), backup)
    }

    func testEditSupersedesPendingViewportAndRecoveryDiscardsIt() throws {
        let (url, initial) = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let storage = CanvasStorage(url: url)
        try storage.save(initial)
        let writer = CanvasPersistence(storage: storage)
        var viewport = initial
        viewport.groups[0].viewport = CanvasViewport(zoom: 2, offsetX: 50, offsetY: 0)
        writer.scheduleViewport(viewport)
        var edited = viewport
        edited.groups[0].name = "New name"
        writer.save(edited, rotatingBackup: true)
        writer.flush()
        XCTAssertEqual(try storage.load()?.groups[0].name, "New name")
        writer.scheduleViewport(edited)
        let restored = try writer.restoreBackup()
        writer.flush()
        XCTAssertEqual(restored, initial)
        XCTAssertEqual(try storage.load(), initial)
    }

    func testProcessTimeoutKillsAnUnresponsiveCommand() throws {
        let start = Date()
        XCTAssertThrowsError(try ProcessRunner.run(executable: "/bin/sh", arguments: ["-c", "exec /bin/sleep 10"], timeout: 0.05)) {
            guard case ProcessRunner.RunError.timedOut = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testProcessDrainsVerboseOutputWithoutPipeDeadlock() throws {
        let result = try ProcessRunner.run(executable: "/usr/bin/head", arguments: ["-c", "200000", "/dev/zero"], timeout: 2)
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.utf8.count, 200_000)
    }

    func testProcessDoesNotSilentlyTruncateOutput() throws {
        XCTAssertThrowsError(try ProcessRunner.run(executable: "/usr/bin/head", arguments: ["-c", "5000000", "/dev/zero"], timeout: 5)) {
            guard case ProcessRunner.RunError.outputLimitExceeded = $0 else { return XCTFail("Unexpected error: \($0)") }
        }
    }

    func testPreviewCacheReusesDecodedImageAndDownsamples() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let cache = CanvasPreviewCache()
        let first = try XCTUnwrap(cache.image(for: data))
        let second = try XCTUnwrap(cache.image(for: data))
        XCTAssertTrue(first === second)
        XCTAssertLessThanOrEqual(first.width, 512)
        XCTAssertLessThanOrEqual(first.height, 512)
        XCTAssertNil(cache.image(for: Data("invalid".utf8)))
    }

    func testLargeRelationshipChainWithCycleHasStableLayers() {
        let cards = (0..<2000).map { _ in ProjectCard(projectID: UUID(), x: 0, y: 0) }
        var edges = (0..<(cards.count - 1)).map {
            ProjectConnection(fromCardID: cards[$0].id, toCardID: cards[$0 + 1].id)
        }
        edges.append(ProjectConnection(fromCardID: cards[1].id, toCardID: cards[0].id))
        let group = ProjectGroup(name: "Chain", cards: cards, connections: edges)
        let result = ProjectLayout.preview(group, mode: .relationships).proposed
        XCTAssertEqual(result.cards[0].x, result.cards[1].x)
        for i in 2..<cards.count { XCTAssertGreaterThan(result.cards[i].x, result.cards[i - 1].x) }
        XCTAssertEqual(result.cards, ProjectLayout.preview(group, mode: .relationships).proposed.cards)
    }
}
