import AppKit
import Carbon
import Combine
import SwiftUI

@MainActor
final class DesktopDisplayController {
    private weak var model: AppModel?
    private var panels: [UUID: NSPanel] = [:]
    private var backgroundPanel: NSPanel?
    private var clipboardPanel: NSPanel?
    private var hotKey: GlobalHotKey?
    private var escapeHotKey: GlobalHotKey?
    private var sceneLayout: DesktopSceneLayout?
    private var sceneKey: SceneKey?
    private var drag: DragState?
    private struct SceneKey: Equatable {
        let groupID: UUID
        let screen: CGRect
        let visible: CGRect
        let scale: Double
        let mode: DesktopDisplayMode
        let cardIDs: [UUID]
    }
    private struct DragState {
        let group: ProjectGroup
        let card: ProjectCard
        let layout: DesktopSceneLayout
        var position: CGPoint
    }
    private var refreshScheduled = false
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        hotKey = GlobalHotKey { [weak model] in model?.toggleDesktopDisplay() }
        // Published values emit before assignment; refresh once after the mutation finishes.
        model.objectWillChange
            .sink { [weak self] in self?.scheduleRefresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: Notification.Name("ProjectCanvasDesktopPreferencesChanged"))
            .merge(with: NotificationCenter.default.publisher(for: .projectCanvasLanguageChanged))
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationActivationChanged),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }

    func show() {
        scheduleRefresh()
    }

    func hide() {
        cancelDrag()
        escapeHotKey = nil
        sceneLayout = nil
        sceneKey = nil
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        backgroundPanel?.orderOut(nil)
        clipboardPanel?.orderOut(nil)
    }

    func handleEscape() {
        guard let model, model.isDesktopDisplayOn else { return }
        if drag != nil {
            cancelDrag()
            refresh()
        } else {
            model.toggleDesktopDisplay()
        }
    }

    private func cancelDrag() {
        drag = nil
        for panel in panels.values { (panel.contentView as? DesktopProjectCardView)?.cancelInteraction() }
    }

    func updateDrag(cardID: UUID, screenDelta: CGSize, ended: Bool) {
        guard let model, model.isDesktopDisplayOn, let group = model.selectedGroup,
              let card = group.cards.first(where: { $0.id == cardID }), let layout = sceneLayout else { return }
        guard let screen = DesktopPreferences.selectedScreen,
              sceneKey == SceneKey(groupID: group.id, screen: screen.frame, visible: cardArea(on: screen, mode: model.desktopDisplayMode), scale: DesktopAppearance.load().cardScale, mode: model.desktopDisplayMode, cardIDs: group.cards.map(\.id)) else {
            cancelDrag(); refresh(); return
        }
        if drag == nil { drag = DragState(group: group, card: card, layout: layout, position: CGPoint(x: card.x, y: card.y)) }
        guard var current = drag, current.group == group, current.card.id == cardID else {
            cancelDrag(); refresh(); return
        }
        current.position = current.layout.dragPosition(for: current.card, screenDelta: screenDelta)
        drag = current
        if ended {
            drag = nil
            model.moveCard(cardID, to: current.position, in: group.id)
            refresh()
        } else {
            var preview = group
            if let index = preview.cards.firstIndex(where: { $0.id == cardID }) {
                preview.cards[index].x = current.position.x
                preview.cards[index].y = current.position.y
            }
            let previewLayout = current.layout.updating(cards: preview.cards)
            if let frame = previewLayout.cardFrames[cardID] { panels[cardID]?.setFrame(frame, display: true) }
            (backgroundPanel?.contentView as? DesktopBackgroundBlurView)?.connections.update(
                connections: previewLayout.connections(in: preview), scale: previewLayout.scale,
                showsLabels: DesktopAppearance.load().showsLabels)
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refresh()
        }
    }

    private func refresh() {
        guard let model else {
            hide()
            return
        }
        guard model.isDesktopDisplayOn else {
            hide()
            return
        }
        guard let group = model.selectedGroup,
              let screen = DesktopPreferences.selectedScreen else {
            hide()
            return
        }

        let cards = group.cards.compactMap { card -> (ProjectCard, String)? in
            guard let project = model.project(for: card) else { return nil }
            return (card, card.customName ?? project.folderName)
        }
        guard !cards.isEmpty || model.desktopDisplayMode == .foregroundOverlay else {
            hide()
            return
        }

        let appearance = DesktopAppearance.load()
        let visible = cardArea(on: screen, mode: model.desktopDisplayMode)
        let key = SceneKey(groupID: group.id, screen: screen.frame, visible: visible, scale: appearance.cardScale, mode: model.desktopDisplayMode, cardIDs: cards.map { $0.0.id })
        if key != sceneKey {
            cancelDrag()
            sceneLayout = DesktopSceneLayout(cards: cards.map { $0.0 }, screenFrame: screen.frame, visibleFrame: visible, requestedScale: appearance.cardScale)
            sceneKey = key
        }
        if let drag, drag.group != group { cancelDrag() }
        var displayedGroup = group
        if let drag, let index = displayedGroup.cards.firstIndex(where: { $0.id == drag.card.id }) {
            displayedGroup.cards[index].x = drag.position.x
            displayedGroup.cards[index].y = drag.position.y
        }
        guard let layout = sceneLayout?.updating(cards: displayedGroup.cards) else { return }
        if drag == nil { sceneLayout = layout }
        if escapeHotKey == nil {
            escapeHotKey = GlobalHotKey(keyCode: UInt32(kVK_Escape), modifiers: 0, identifier: 2) { [weak self] in self?.handleEscape() }
        }
        showBackgroundBlur(on: screen, connections: layout.connections(in: displayedGroup), scale: layout.scale, appearance: appearance)
        let visibleCardIDs = Set(cards.map { $0.0.id })

        for (card, title) in cards {
            guard let frame = layout.cardFrames[card.id] else { continue }
            let panel = panels[card.id] ?? makePanel()
            if let view = panel.contentView as? DesktopProjectCardView {
                view.update(title: title, color: card.color.nsColor)
            } else {
                let cardID = card.id
                panel.contentView = DesktopProjectCardView(title: title, color: card.color.nsColor) { [weak model] in
                    guard let model,
                          let currentCard = model.selectedGroup?.cards.first(where: { $0.id == cardID }),
                          let project = model.project(for: currentCard) else { return }
                    model.openProject(project)
                }
            }
            (panel.contentView as? DesktopProjectCardView)?.onDrag = { [weak self] delta, ended in
                self?.updateDrag(cardID: card.id, screenDelta: delta, ended: ended)
            }
            panel.level = cardWindowLevel
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels[card.id] = panel
        }

        for cardID in panels.keys.filter({ !visibleCardIDs.contains($0) }) {
            panels.removeValue(forKey: cardID)?.orderOut(nil)
        }

        if model.desktopDisplayMode == .foregroundOverlay {
            showClipboardShelf(on: screen, model: model)
        } else {
            clipboardPanel?.orderOut(nil)
        }
    }

    private func showBackgroundBlur(on screen: NSScreen, connections: [DesktopSceneLayout.Connection], scale: CGFloat, appearance: DesktopAppearance) {
        let panel = backgroundPanel ?? makeBackgroundPanel()
        if panel.contentView as? DesktopBackgroundBlurView == nil {
            panel.contentView = DesktopBackgroundBlurView(frame: .zero)
        }
        panel.setFrame(screen.frame, display: true)
        panel.level = backgroundWindowLevel
        if let blur = panel.contentView as? DesktopBackgroundBlurView {
            blur.onDismiss = { [weak model = self.model] in
                guard let model, model.isDesktopDisplayOn else { return }
                model.toggleDesktopDisplay()
            }
            blur.update(appearance: appearance)
            blur.connections.update(connections: connections, scale: scale, showsLabels: appearance.showsLabels)
        }
        // The background is part of the desktop presentation, even while this app is active.
        panel.orderFrontRegardless()
        backgroundPanel = panel
    }

    private func makeBackgroundPanel() -> NSPanel {
        let panel = DesktopPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
        panel.collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        return panel
    }

    private var shelfExpanded: Bool {
        UserDefaults.standard.object(forKey: "clipboardShelfExpanded") as? Bool ?? true
    }

    private func cardArea(on screen: NSScreen, mode: DesktopDisplayMode) -> CGRect {
        mode == .foregroundOverlay
            ? DesktopOverlayLayout(visibleFrame: screen.visibleFrame, expanded: shelfExpanded).cards
            : screen.visibleFrame.insetBy(dx: 24, dy: 24)
    }

    private func showClipboardShelf(on screen: NSScreen, model: AppModel) {
        let panel = clipboardPanel ?? makePanel()
        if !(panel.contentView is DesktopClipboardHostingView) {
            let shelf = ClipboardShelfView(history: model.clipboardHistory, onClose: { [weak model] in
                guard let model, model.isDesktopDisplayOn else { return }
                model.toggleDesktopDisplay()
            })
            panel.contentView = DesktopClipboardHostingView(rootView: shelf)
        }
        model.clipboardHistory.start()
        panel.level = .floating
        panel.ignoresMouseEvents = false
        panel.setFrame(DesktopOverlayLayout(visibleFrame: screen.visibleFrame, expanded: shelfExpanded).shelf, display: true)
        panel.orderFrontRegardless()
        clipboardPanel = panel
    }

    private func makePanel() -> NSPanel {
        let panel = DesktopPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = cardWindowLevel
        panel.collectionBehavior = [.moveToActiveSpace, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        return panel
    }

    @objc private func screenParametersChanged() {
        cancelDrag()
        sceneKey = nil
        scheduleRefresh()
    }

    @objc private func applicationActivationChanged() {
        scheduleRefresh()
    }

    private var backgroundWindowLevel: NSWindow.Level {
        model?.desktopDisplayMode == .foregroundOverlay ? .floating :
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }

    private var cardWindowLevel: NSWindow.Level {
        model?.desktopDisplayMode == .foregroundOverlay ? .floating :
            NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)))
    }
}

// Clicking a card or close control must not steal focus from the user's editor.
private final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopBackgroundBlurView: NSView {
    var onDismiss: (() -> Void)?
    let effect = NSVisualEffectView(frame: .zero)
    private let dimming = NSView(frame: .zero)
    let connections = DesktopConnectionView(frame: .zero)

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Decorations share one dismiss target; card windows remain above this background.
        guard !isHidden, alphaValue > 0, frame.contains(point) else { return nil }
        return self
    }

    override func mouseUp(with event: NSEvent) { onDismiss?() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        dimming.wantsLayer = true
        for view in [effect, dimming, connections] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    func update(appearance: DesktopAppearance) {
        // Blend the native material independently so lines never fade with the blur.
        effect.alphaValue = appearance.blur
        effect.isHidden = appearance.blur == 0
        dimming.layer?.backgroundColor = NSColor.black.withAlphaComponent(appearance.dimming).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class DesktopProjectCardView: NSView {
    static let size = CGSize(width: 210, height: 100)

    private var title: String
    private var color: NSColor
    private let action: () -> Void
    var onDrag: ((CGSize, Bool) -> Void)?
    private var pointerDown: CGPoint?
    private var didDrag = false
    private var cancelled = false

    override var isFlipped: Bool { true }

    init(title: String, color: NSColor, action: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func update(title: String, color: NSColor) {
        guard self.title != title || !self.color.isEqual(color) else { return }
        self.title = title
        self.color = color
        needsDisplay = true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func cancelInteraction() {
        cancelled = true
        pointerDown = nil
    }

    private func screenPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }

    override func mouseDown(with event: NSEvent) {
        pointerDown = screenPoint(event)
        didDrag = false
        cancelled = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !cancelled, let start = pointerDown else { return }
        let point = screenPoint(event)
        let delta = CGSize(width: point.x - start.x, height: point.y - start.y)
        if hypot(delta.width, delta.height) >= 4 { didDrag = true }
        if didDrag { onDrag?(delta, false) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        (NSColor.windowBackgroundColor.blended(withFraction: 0.22, of: color) ?? color).withAlphaComponent(0.96).setFill()
        card.fill()
        NSColor.separatorColor.setStroke()
        card.lineWidth = 1
        card.stroke()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let text = title as NSString
        let availableWidth = max(0, bounds.width - 32)
        let measured = text.boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let textHeight = min(measured.height, max(0, bounds.height - 16))
        text.draw(
            with: NSRect(x: 16, y: (bounds.height - textHeight) / 2, width: availableWidth, height: textHeight),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    override func mouseUp(with event: NSEvent) {
        defer { pointerDown = nil; didDrag = false }
        guard !cancelled, let start = pointerDown else { return }
        if didDrag {
            let point = screenPoint(event)
            onDrag?(CGSize(width: point.x - start.x, height: point.y - start.y), true)
        } else { action() }
    }
}

/// The clipboard shelf handles its own clicks and scroll gestures, never the backdrop's dismiss action.
private final class DesktopClipboardHostingView: NSHostingView<ClipboardShelfView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
