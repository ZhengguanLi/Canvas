import AppKit
import XCTest
@testable import ProjectCanvas

final class DesktopDragTests: XCTestCase {
    @MainActor func testDesktopDragSavesOnceAndEscapeCancelsBeforeDismissing() async throws {
        _ = NSApplication.shared
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("Requires window server") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = "DesktopDragTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url, preferences: preferences)
        model.addProject(folderURL: directory)
        model.toggleDesktopDisplay()
        defer { if model.isDesktopDisplayOn { model.toggleDesktopDisplay() } }
        try await Task.sleep(for: .milliseconds(100))
        let controller = try XCTUnwrap(model.desktopDisplayController)
        let group = try XCTUnwrap(model.selectedGroup)
        let card = try XCTUnwrap(group.cards.first)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.contentView is DesktopProjectCardView })
        let originalFrame = panel.frame
        let before = try Data(contentsOf: url)
        controller.updateDrag(cardID: card.id, screenDelta: CGSize(width: 30, height: -20), ended: false)
        XCTAssertEqual(try Data(contentsOf: url), before)
        controller.handleEscape()
        XCTAssertTrue(model.isDesktopDisplayOn)
        XCTAssertEqual(model.selectedGroup?.cards, group.cards)
        XCTAssertEqual(try Data(contentsOf: url), before)
        controller.updateDrag(cardID: card.id, screenDelta: CGSize(width: 30, height: -20), ended: false)
        controller.updateDrag(cardID: card.id, screenDelta: CGSize(width: 30, height: -20), ended: true)
        let changed = try XCTUnwrap(model.selectedGroup?.cards.first)
        XCTAssertEqual(panel.frame.minX - originalFrame.minX, 30, accuracy: 0.01)
        XCTAssertEqual(panel.frame.minY - originalFrame.minY, -20, accuracy: 0.01)
        XCTAssertGreaterThan(changed.x, card.x)
        XCTAssertGreaterThan(changed.y, card.y)
        XCTAssertEqual(AppModel(storageURL: url, preferences: preferences).selectedGroup?.cards.first, changed)
        model.undo()
        XCTAssertEqual(model.selectedGroup?.cards, group.cards)
        controller.handleEscape()
        XCTAssertFalse(model.isDesktopDisplayOn)
    }

    @MainActor func testCenteredDragPastCanvasOriginKeepsOtherCardsStableAndSupportsUndoRedo() async throws {
        _ = NSApplication.shared
        guard let screen = DesktopPreferences.selectedScreen else { throw XCTSkip("Requires window server") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let secondDirectory = directory.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let suite = "DesktopDragTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("canvas.json")
        let model = AppModel(storageURL: url, preferences: preferences)
        model.addProject(folderURL: directory)
        model.addProject(folderURL: secondDirectory)
        let groupID = try XCTUnwrap(model.selectedGroupID)
        let cardID = try XCTUnwrap(model.selectedGroup?.cards.first?.id)
        model.moveCard(cardID, to: CGPoint(x: 20, y: 20), in: groupID)
        let originalGroup = try XCTUnwrap(model.selectedGroup)
        model.setDesktopDisplayMode(.foregroundOverlay)
        model.toggleDesktopDisplay()
        defer { if model.isDesktopDisplayOn { model.toggleDesktopDisplay() } }
        try await Task.sleep(for: .milliseconds(100))
        let controller = try XCTUnwrap(model.desktopDisplayController)
        let panels = NSApp.windows.filter { $0.isVisible && $0.contentView is DesktopProjectCardView }
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(panels.count, 2)
        let moving = try XCTUnwrap(panels.first)
        let stationary = try XCTUnwrap(panels.last)
        let movingFrame = moving.frame
        let stationaryFrame = stationary.frame
        let spaceToLeft = movingFrame.minX - screen.visibleFrame.minX - 24
        guard spaceToLeft > 20 else { throw XCTSkip("Requires room left of the centered graph") }
        let distance = min(80, spaceToLeft / 2)
        controller.updateDrag(cardID: cardID, screenDelta: CGSize(width: -distance, height: 0), ended: false)
        XCTAssertEqual(moving.frame.minX, movingFrame.minX - distance, accuracy: 0.001)
        controller.updateDrag(cardID: cardID, screenDelta: CGSize(width: -distance, height: 0), ended: true)
        let movedGroup = try XCTUnwrap(model.selectedGroup)
        XCTAssertGreaterThan(try XCTUnwrap(movedGroup.coordinateOffset).x, 0)
        XCTAssertEqual(moving.frame.minX, movingFrame.minX - distance, accuracy: 0.001)
        XCTAssertEqual(stationary.frame, stationaryFrame)
        XCTAssertTrue(movedGroup.cards.allSatisfy { $0.x >= 20 && $0.y >= 20 })
        XCTAssertEqual(AppModel(storageURL: url, preferences: preferences).selectedGroup, movedGroup)
        model.undo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selectedGroup, originalGroup)
        XCTAssertEqual(moving.frame, movingFrame)
        XCTAssertEqual(stationary.frame, stationaryFrame)
        model.redo()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(model.selectedGroup, movedGroup)
        XCTAssertEqual(moving.frame.minX, movingFrame.minX - distance, accuracy: 0.001)
        XCTAssertEqual(stationary.frame, stationaryFrame)
    }

    @MainActor func testCancelledDragCannotOpenProjectOnMouseUp() {
        var opens = 0
        var movements: [Bool] = []
        let view = DesktopProjectCardView(title: "Test", color: .blue, action: { opens += 1 })
        view.onDrag = { _, ended in movements.append(ended) }
        func event(_ type: NSEvent.EventType, _ x: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 0), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        view.mouseDown(with: event(.leftMouseDown, 0))
        view.mouseDragged(with: event(.leftMouseDragged, 20))
        view.cancelInteraction()
        view.mouseDragged(with: event(.leftMouseDragged, 30))
        view.mouseUp(with: event(.leftMouseUp, 30))
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(movements, [false])
        view.mouseDown(with: event(.leftMouseDown, 0))
        view.mouseDragged(with: event(.leftMouseDragged, 20))
        view.mouseUp(with: event(.leftMouseUp, 20))
        XCTAssertEqual(opens, 0)
        XCTAssertEqual(movements, [false, false, true])
        view.mouseDown(with: event(.leftMouseDown, 0))
        view.mouseUp(with: event(.leftMouseUp, 0))
        XCTAssertEqual(opens, 1)
    }

    func testInverseTransformAndStableFrameOnOffsetScreen() {
        let card = ProjectCard(projectID: UUID(), x: 300, y: 300)
        let screen = CGRect(x: -1400, y: -300, width: 1200, height: 800)
        let layout = DesktopSceneLayout(cards: [card], screenFrame: screen, visibleFrame: screen, requestedScale: 0.6)
        let position = layout.dragPosition(for: card, screenDelta: CGSize(width: 60, height: -30))
        XCTAssertEqual(position.x, 400, accuracy: 0.001)
        XCTAssertEqual(position.y, 350, accuracy: 0.001)
        var moved = card
        moved.x = position.x; moved.y = position.y
        let updated = layout.updating(cards: [moved])
        XCTAssertEqual(updated.cardFrames[card.id]!.minX - layout.cardFrames[card.id]!.minX, 60, accuracy: 0.001)
        XCTAssertEqual(updated.cardFrames[card.id]!.minY - layout.cardFrames[card.id]!.minY, -30, accuracy: 0.001)
    }

    func testInitialDesktopLayoutIsCentered() throws {
        let cards = [ProjectCard(projectID: UUID(), x: 20, y: 20),
                     ProjectCard(projectID: UUID(), x: 400, y: 200)]
        let screen = CGRect(x: -1600, y: -200, width: 1400, height: 1000)
        let available = screen.insetBy(dx: 24, dy: 100)
        let layout = DesktopSceneLayout(cards: cards, screenFrame: screen, visibleFrame: available)
        let bounds = layout.cardFrames.values.reduce(CGRect.null) { $0.union($1) }
        XCTAssertEqual(bounds.midX, available.midX, accuracy: 0.001)
        XCTAssertEqual(bounds.midY, available.midY, accuracy: 0.001)
    }

    func testDraggingReachesVisibleLeftAndTopEdgesOnOffsetScreen() throws {
        let card = ProjectCard(projectID: UUID(), x: 300, y: 300)
        let screen = CGRect(x: -1600, y: -200, width: 1400, height: 1000)
        let available = screen.insetBy(dx: 24, dy: 100)
        let layout = DesktopSceneLayout(cards: [card], screenFrame: screen, visibleFrame: available, requestedScale: 0.6)
        let position = layout.dragPosition(for: card, screenDelta: CGSize(width: -10000, height: 10000))
        var moved = card
        moved.x = position.x
        moved.y = position.y
        let frame = try XCTUnwrap(layout.updating(cards: [moved]).cardFrames[card.id])
        XCTAssertEqual(frame.minX, available.minX, accuracy: 0.001)
        XCTAssertEqual(frame.maxY, available.maxY, accuracy: 0.001)
    }

    func testDragClampsToDisplayAndCanvas() {
        let card = ProjectCard(projectID: UUID(), x: 300, y: 300)
        let screen = CGRect(x: -1400, y: -300, width: 1200, height: 800)
        let layout = DesktopSceneLayout(cards: [card], screenFrame: screen, visibleFrame: screen)
        let position = layout.dragPosition(for: card, screenDelta: CGSize(width: -10000, height: 10000))
        var moved = card
        moved.x = position.x; moved.y = position.y
        XCTAssertTrue(screen.contains(layout.updating(cards: [moved]).cardFrames[card.id]!))
    }
}
