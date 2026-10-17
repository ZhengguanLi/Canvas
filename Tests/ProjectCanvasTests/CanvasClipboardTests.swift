import AppKit
import SwiftUI
import XCTest
@testable import ProjectCanvas

final class CanvasClipboardTests: XCTestCase {
    @MainActor private func withModel(_ body: (AppModel, URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let name = "CanvasClipboardTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: name))
        defer {
            preferences.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("canvas.json")
        try body(AppModel(storageURL: url, preferences: preferences), url)
    }

    private func imageContent() throws -> CanvasClipboardContent {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let pixels = try XCTUnwrap(bitmap.bitmapData)
        for y in 0..<4 {
            for x in 0..<4 {
                let offset = y * bitmap.bytesPerRow + x * 4
                pixels[offset] = 40
                pixels[offset + 1] = 110
                pixels[offset + 2] = 220
                pixels[offset + 3] = 255
            }
        }
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        return .image(data: png, type: NSPasteboard.PasteboardType.png.rawValue, preview: png)
    }

    @MainActor func testHistoryItemCanBePlacedMovedSavedAndUndoneWithoutMovingProjects() throws {
        try withModel { model, url in
            model.addProject(folderURL: url.deletingLastPathComponent())
            let groupID = try XCTUnwrap(model.selectedGroupID)
            let projectCard = try XCTUnwrap(model.selectedGroup?.cards.first)
            model.clipboardHistory.receiveText("An idea for this project")
            let item = try XCTUnwrap(model.clipboardHistory.texts.first)
            XCTAssertTrue(model.addClipboardItem(ClipboardCanvasTransfer(id: item.id, kind: .text), to: groupID,
                                                 at: CGPoint(x: 650, y: 320)))
            let contentCard = try XCTUnwrap(model.selectedGroup?.cards.last)
            XCTAssertNil(contentCard.projectID)
            XCTAssertEqual(contentCard.clipboard, .text(item.text))
            XCTAssertEqual(model.selectedGroup?.cards.first, projectCard)
            model.clipboardHistory.clearTexts()
            model.moveCard(contentCard.id, to: CGPoint(x: 900, y: 500), in: groupID)
            model.flushPersistence()
            let stored = try CanvasStorage.decode(Data(contentsOf: url))
            XCTAssertEqual(stored.groups.first?.cards.last?.x, 900)
            XCTAssertEqual(stored.groups.first?.cards.last?.clipboard, .text(item.text))
            model.undo()
            XCTAssertEqual(model.selectedGroup?.cards.last, contentCard)
            model.undo()
            XCTAssertEqual(model.selectedGroup?.cards, [projectCard])
            model.redo()
            XCTAssertEqual(model.selectedGroup?.cards.last, contentCard)
            XCTAssertFalse(model.addClipboardItem(ClipboardCanvasTransfer(id: item.id, kind: .text), to: groupID))
        }
    }

    @MainActor func testMixedCanvasSupportsConnectionsRegionsBulkMovementAndRemoval() throws {
        try withModel { model, url in
            model.addProject(folderURL: url.deletingLastPathComponent())
            let groupID = try XCTUnwrap(model.selectedGroupID)
            XCTAssertTrue(model.addClipboardContent(try imageContent(), to: groupID, at: CGPoint(x: 450, y: 250)))
            let cards = try XCTUnwrap(model.selectedGroup?.cards)
            guard cards.count == 2 else { XCTFail("Expected project and clipboard cards"); return }
            model.connectCards(cards[0].id, cards[1].id, in: groupID)
            XCTAssertEqual(model.selectedGroup?.connections.count, 1)
            let ids = Set(cards.map(\.id))
            model.addRegion(name: "Research", color: .blue, cardIDs: ids, in: groupID)
            XCTAssertEqual(model.selectedGroup?.regions.count, 1)
            model.moveCards(ids: ids, by: CGSize(width: 32, height: 64), in: groupID)
            XCTAssertEqual(model.selectedGroup?.cards.last?.x, cards[1].x + 32)
            XCTAssertEqual(model.selectedGroup?.cards.first?.y, cards[0].y + 64)
            model.removeCards([cards[1].id], from: groupID)
            XCTAssertEqual(model.selectedGroup?.cards.count, 1)
            XCTAssertTrue(model.selectedGroup?.connections.isEmpty ?? false)
            model.undo()
            XCTAssertEqual(model.selectedGroup?.cards.count, 2)
            XCTAssertEqual(model.selectedGroup?.connections.count, 1)
            model.flushPersistence()
            _ = try CanvasStorage.decode(Data(contentsOf: url))
        }
    }

    @MainActor func testTextAndImagesExportAndImportWithFreshCardAndConnectionIDs() throws {
        try withModel { model, url in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            XCTAssertTrue(model.addClipboardContent(.text("Keep this note"), to: groupID))
            let image = try imageContent()
            XCTAssertTrue(model.addClipboardContent(image, to: groupID))
            let original = try XCTUnwrap(model.selectedGroup)
            guard original.cards.count == 2 else { XCTFail("Expected text and image cards"); return }
            model.connectCards(original.cards[0].id, original.cards[1].id, in: groupID)
            let exported = url.deletingLastPathComponent().appendingPathComponent("export.json")
            model.exportGroup(groupID, to: exported)
            model.importGroups(from: exported, pathFrom: "", pathTo: "")
            let imported = try XCTUnwrap(model.selectedGroup)
            XCTAssertNotEqual(imported.id, groupID)
            XCTAssertEqual(imported.cards.map(\.clipboard), original.cards.map(\.clipboard))
            XCTAssertTrue(Set(imported.cards.map(\.id)).isDisjoint(with: Set(original.cards.map(\.id))))
            XCTAssertEqual(imported.connections.first?.fromCardID, imported.cards.first?.id)
            XCTAssertEqual(imported.connections.first?.toCardID, imported.cards.last?.id)
            XCTAssertTrue(imported.cards.allSatisfy { $0.projectID == nil })
            model.flushPersistence()
            _ = try CanvasStorage.decode(Data(contentsOf: url))
        }
    }

    @MainActor func testCanvasCardClicksOnlySelectAndShiftTogglesSelection() throws {
        try withModel { model, _ in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            XCTAssertTrue(model.addClipboardContent(.text("First note"), to: groupID, at: CGPoint(x: 100, y: 100)))
            XCTAssertTrue(model.addClipboardContent(.text("Second note"), to: groupID, at: CGPoint(x: 400, y: 100)))
            let group = try XCTUnwrap(model.selectedGroup)
            var selected: Set<UUID> = []
            var connection: UUID? = UUID()
            let pasteboardChanges = NSPasteboard.general.changeCount
            let board = CanvasBoard(model: model, group: group, zoom: 1, isEditing: true, snapToGrid: true,
                selectedCardIDs: Binding(get: { selected }, set: { selected = $0 }),
                selectedConnectionID: Binding(get: { connection }, set: { connection = $0 }),
                isConnecting: .constant(false), firstConnectionCardID: .constant(nil), highlightDirection: 0,
                onOpenSettings: { _ in }, onRelocate: { _ in })
            board.handleCardClick(group.cards[0], extendingSelection: false)
            XCTAssertEqual(selected, [group.cards[0].id])
            XCTAssertNil(connection)
            board.handleCardClick(group.cards[1], extendingSelection: true)
            XCTAssertEqual(selected, Set(group.cards.map(\.id)))
            board.handleCardClick(group.cards[0], extendingSelection: true)
            XCTAssertEqual(selected, [group.cards[1].id])
            board.handleCardClick(group.cards[0], extendingSelection: false)
            XCTAssertEqual(selected, [group.cards[0].id])
            XCTAssertEqual(NSPasteboard.general.changeCount, pasteboardChanges)
            XCTAssertEqual(model.selectedGroup, group)
        }
    }

    @MainActor func testSelectAllAndConnectingFromEitherSelectedCard() throws {
        try withModel { model, _ in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            XCTAssertTrue(model.addClipboardContent(.text("First"), to: groupID, at: CGPoint(x: 100, y: 100)))
            XCTAssertTrue(model.addClipboardContent(.text("Second"), to: groupID, at: CGPoint(x: 400, y: 100)))
            let group = try XCTUnwrap(model.selectedGroup)
            var selected: Set<UUID> = []
            var connection: UUID? = UUID()
            var connecting = true
            var first: UUID? = group.cards[0].id
            let board = CanvasBoard(model: model, group: group, zoom: 1, isEditing: true, snapToGrid: true,
                selectedCardIDs: Binding(get: { selected }, set: { selected = $0 }),
                selectedConnectionID: Binding(get: { connection }, set: { connection = $0 }),
                isConnecting: Binding(get: { connecting }, set: { connecting = $0 }),
                firstConnectionCardID: Binding(get: { first }, set: { first = $0 }), highlightDirection: 0,
                onOpenSettings: { _ in }, onRelocate: { _ in })
            board.handleSelectAll()
            XCTAssertEqual(selected, Set(group.cards.map(\.id)))
            XCTAssertNil(connection)
            XCTAssertFalse(connecting)
            XCTAssertNil(first)
            board.connectSelectedCards(from: group.cards[0].id)
            XCTAssertEqual(model.selectedGroup?.connections.first?.fromCardID, group.cards[0].id)
            XCTAssertEqual(model.selectedGroup?.connections.first?.toCardID, group.cards[1].id)
            XCTAssertNotNil(connection)
            board.connectSelectedCards(from: group.cards[1].id)
            XCTAssertEqual(model.selectedGroup?.connections.count, 2)
            board.connectSelectedCards(from: group.cards[0].id)
            XCTAssertEqual(model.selectedGroup?.connections.count, 2)
            selected = [group.cards[0].id]
            board.connectSelectedCards(from: group.cards[0].id)
            XCTAssertEqual(model.selectedGroup?.connections.count, 2)
            model.undo()
            XCTAssertEqual(model.selectedGroup?.connections.count, 1)
            model.undo()
            XCTAssertTrue(model.selectedGroup?.connections.isEmpty == true)
        }
    }

    @MainActor func testMixedCanvasRendersTextAndImageCards() throws {
        _ = NSApplication.shared
        try withModel { model, url in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            model.addProject(folderURL: url.deletingLastPathComponent())
            XCTAssertTrue(model.addClipboardContent(.text("Ideas and reference material for this project"), to: groupID, at: CGPoint(x: 360, y: 120)))
            XCTAssertTrue(model.addClipboardContent(try imageContent(), to: groupID, at: CGPoint(x: 620, y: 120)))
            let group = try XCTUnwrap(model.selectedGroup)
            let board = CanvasBoard(model: model, group: group, zoom: 1, isEditing: true, snapToGrid: true,
                selectedCardIDs: .constant([group.cards[1].id]), selectedConnectionID: .constant(nil),
                isConnecting: .constant(false), firstConnectionCardID: .constant(nil), highlightDirection: 0,
                onOpenSettings: { _ in }, onRelocate: { _ in })
            let host = NSHostingView(rootView: board.environment(\.colorScheme, .light))
            host.appearance = NSAppearance(named: .aqua)
            host.frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let imagePixel = try XCTUnwrap(bitmap.colorAt(x: 725, y: 175)?.usingColorSpace(.sRGB))
            let borderPixel = try XCTUnwrap(bitmap.colorAt(x: 630, y: 205)?.usingColorSpace(.sRGB))
            XCTAssertGreaterThan(abs(imagePixel.redComponent - borderPixel.redComponent), 0.04)
            if let path = ProcessInfo.processInfo.environment["PROJECTCANVAS_CONTENT_PREVIEW"] {
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
            }
        }
    }

    func testMainCanvasDropRespectsZoomAndCardCenter() {
        for zoom in [0.5, 1, 2] {
            let point = CGPoint(x: 605 * zoom, y: 350 * zoom)
            XCTAssertEqual(CanvasGeometry.positionForDrop(at: point, zoom: zoom), CGPoint(x: 500, y: 300))
        }
        XCTAssertEqual(CanvasGeometry.positionForDrop(at: .zero, zoom: 1), CGPoint(x: 20, y: 20))
        XCTAssertEqual(CanvasGeometry.positionForDrop(at: CGPoint(x: 210, y: 100), zoom: 2,
            scrollOffset: CGPoint(x: 1000, y: 600)), CGPoint(x: 500, y: 300))
    }

    func testDesktopDropCoordinatesMatchSavedContentCardOnOffsetMonitor() {
        let card = ProjectCard(clipboard: .text("A note"), x: 300, y: 400)
        let frame = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let layout = DesktopSceneLayout(cards: [card], screenFrame: frame, visibleFrame: frame.insetBy(dx: 24, dy: 24), requestedScale: 0.8)
        let displayed = layout.cardFrames[card.id]!
        let point = layout.canvasPosition(atScreenPoint: CGPoint(x: displayed.midX, y: displayed.midY))
        XCTAssertEqual(point.x, card.x, accuracy: 0.001)
        XCTAssertEqual(point.y, card.y, accuracy: 0.001)
    }

    @MainActor func testExplicitClipboardCopyPreservesOriginalPayload() throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        guard pasteboard.setString("probe", forType: .string) else { throw XCTSkip("Requires pasteboard service access") }
        XCTAssertTrue(CanvasClipboardContent.text("Hello 世界").copy(to: pasteboard))
        XCTAssertEqual(pasteboard.string(forType: .string), "Hello 世界")
        let image = try imageContent()
        XCTAssertTrue(image.copy(to: pasteboard))
        if case .image(let original, _, _) = image { XCTAssertEqual(pasteboard.data(forType: .png), original) }
    }

    @MainActor func testInvalidContentAndAmbiguousCardsAreRejected() throws {
        try withModel { model, url in
            let groupID = try XCTUnwrap(model.selectedGroupID)
            XCTAssertFalse(model.addClipboardContent(.text(""), to: groupID))
            XCTAssertFalse(model.addClipboardContent(.text(String(repeating: "x", count: 256 * 1024 + 1)), to: groupID))
            XCTAssertFalse(model.addClipboardContent(.text("Invalid position"), to: groupID, at: CGPoint(x: CGFloat.nan, y: 10)))
            XCTAssertFalse(CanvasClipboardContent.image(data: Data([0]), type: "public.png", preview: Data([0])).isValid)
            model.addProject(folderURL: url.deletingLastPathComponent())
            let project = try XCTUnwrap(model.projects.first)
            var card = ProjectCard(clipboard: .text("Ambiguous"), x: 20, y: 20)
            card.projectID = project.id
            let invalid = ProjectCanvasData(projects: [project], groups: [ProjectGroup(name: "Invalid", cards: [card])], selectedGroupID: nil)
            XCTAssertThrowsError(try CanvasStorage.decode(JSONEncoder().encode(invalid)))
        }
    }
}
