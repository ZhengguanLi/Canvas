import AppKit
import Carbon
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DesktopDisplayController {
    private weak var model: AppModel?
    private var panels: [UUID: NSPanel] = [:]
    private var backgroundPanel: NSPanel?
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

    /// Registers the user's shortcut, or none while a new one is being recorded.
    private func registerToggleHotKey() {
        hotKey = nil  // Unregister first so re-registering the same combination succeeds.
        guard !HotKeyStatus.shared.isRecording else { return }
        let key = GlobalHotKey(shortcut: HotKeyShortcut.load()) { [weak model] in model?.toggleDesktopDisplay() }
        hotKey = key
        HotKeyStatus.shared.registrationFailed = !key.isRegistered
    }

    init(model: AppModel) {
        self.model = model
        registerToggleHotKey()
        NotificationCenter.default.publisher(for: .projectCanvasHotKeyChanged)
            .sink { [weak self] _ in self?.registerToggleHotKey() }
            .store(in: &cancellables)
        // Published values emit before assignment; refresh once after the mutation finishes.
        model.objectWillChange
            .sink { [weak self] in self?.scheduleRefresh() }
            .store(in: &cancellables)
        model.clipboardHistory.objectWillChange
            .sink { [weak self] in self?.scheduleRefresh() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: Notification.Name("ProjectCanvasDesktopPreferencesChanged"))
            .merge(with: NotificationCenter.default.publisher(for: .projectCanvasLanguageChanged))
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.applicationActivated(processID: application.processIdentifier)
            }
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
        (backgroundPanel?.contentView as? DesktopBackgroundBlurView)?.hideClotheslines()
    }

    func handleEscape() {
        guard let model, model.isDesktopDisplayOn else { return }
        if drag != nil {
            cancelDrag()
            refresh()
        } else if model.desktopDisplayMode == .foregroundOverlay,
                  Self.restoreClipboardSize(in: .standard) {
            refresh()
        } else {
            model.toggleDesktopDisplay()
        }
    }

    static func restoreClipboardSize(in preferences: UserDefaults) -> Bool {
        guard preferences.object(forKey: "clipboardShelfVisible") as? Bool ?? true else { return false }
        let isEnlarged = preferences.bool(forKey: "clipboardShelfFullScreen")
        guard isEnlarged else { return false }
        preferences.set(false, forKey: "clipboardShelfFullScreen")
        return true
    }

    func applicationActivated(processID: pid_t) {
        guard let model, model.isDesktopDisplayOn,
              model.desktopDisplayMode == .foregroundOverlay,
              processID != ProcessInfo.processInfo.processIdentifier else { return }
        model.toggleDesktopDisplay()
    }

    private func cancelDrag() {
        drag = nil
        (backgroundPanel?.contentView as? DesktopBackgroundBlurView)?.connections.updateGuides([])
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
        // Snap to other cards like the main canvas; the threshold is 6 points on screen.
        let raw = current.layout.dragPosition(for: current.card, screenDelta: screenDelta)
        let alignment = CanvasAlignment.resolve(
            cards: group.cards, movingIDs: [cardID],
            proposed: CGSize(width: raw.x - current.card.x, height: raw.y - current.card.y),
            zoom: current.layout.scale, enabled: CanvasAlignment.isEnabled, clampsToOrigin: false)
        current.position = CGPoint(x: current.card.x + alignment.offset.width, y: current.card.y + alignment.offset.height)
        drag = current
        let connectionView = (backgroundPanel?.contentView as? DesktopBackgroundBlurView)?.connections
        if ended {
            drag = nil
            connectionView?.updateGuides([])
            model.moveDesktopCard(cardID, to: current.position, in: group.id)
            refresh()
        } else {
            var preview = group
            if let index = preview.cards.firstIndex(where: { $0.id == cardID }) {
                preview.cards[index].x = current.position.x
                preview.cards[index].y = current.position.y
            }
            let previewLayout = current.layout.updating(cards: preview.cards)
            if let frame = previewLayout.cardFrames[cardID] { panels[cardID]?.setFrame(frame, display: true) }
            connectionView?.update(
                connections: previewLayout.connections(in: preview), scale: previewLayout.scale,
                showsLabels: DesktopAppearance.load().showsLabels)
            connectionView?.updateGuides(previewLayout.localGuides(alignment.guides))
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
            if let content = card.clipboard { return (card, card.customName ?? content.title) }
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
            sceneLayout = DesktopSceneLayout(cards: cards.map { $0.0 }, screenFrame: screen.frame, visibleFrame: visible,
                requestedScale: appearance.cardScale, coordinateOffset: group.coordinateOffset ?? .zero,
                alignsToTop: model.desktopDisplayMode == .foregroundOverlay &&
                    (UserDefaults.standard.object(forKey: "clipboardShelfVisible") as? Bool ?? true))
            sceneKey = key
        }
        if let drag, drag.group != group { cancelDrag() }
        var displayedGroup = group
        if let drag, let index = displayedGroup.cards.firstIndex(where: { $0.id == drag.card.id }) {
            displayedGroup.cards[index].x = drag.position.x
            displayedGroup.cards[index].y = drag.position.y
        }
        guard let layout = sceneLayout?.updating(cards: displayedGroup.cards, coordinateOffset: displayedGroup.coordinateOffset ?? .zero) else { return }
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
                view.update(title: title, color: card.color.nsColor, clipboard: card.clipboard)
            } else {
                let cardID = card.id
                panel.contentView = DesktopProjectCardView(title: title, color: card.color.nsColor) { [weak model] in
                    guard let model,
                          let currentCard = model.selectedGroup?.cards.first(where: { $0.id == cardID }) else { return }
                    if let content = currentCard.clipboard { model.copyClipboardContent(content) }
                    else if let project = model.project(for: currentCard) { model.openProject(project) }
                }
            }
            (panel.contentView as? DesktopProjectCardView)?.update(title: title, color: card.color.nsColor, clipboard: card.clipboard)
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
            (backgroundPanel?.contentView as? DesktopBackgroundBlurView)?.hideClotheslines()
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
            blur.onClipboardDrop = { [weak self] item, screenPoint in
                guard let self, let model = self.model, model.isDesktopDisplayOn,
                      let groupID = model.selectedGroupID, let layout = self.sceneLayout else { return false }
                return model.addClipboardItem(item, to: groupID, at: layout.canvasPosition(atScreenPoint: screenPoint))
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

    private var clotheslineHeight: Double {
        ClipboardAppearance.load().canvasClotheslineHeight
    }

    private func cardArea(on screen: NSScreen, mode: DesktopDisplayMode) -> CGRect {
        mode == .foregroundOverlay
            ? DesktopOverlayLayout(visibleFrame: screen.visibleFrame, expanded: true, shelfHeight: clotheslineHeight,
                visible: UserDefaults.standard.object(forKey: "clipboardShelfVisible") as? Bool ?? true).cards
            : screen.visibleFrame.insetBy(dx: 24, dy: 24)
    }

    private func showClipboardShelf(on screen: NSScreen, model: AppModel) {
        guard let background = backgroundPanel?.contentView as? DesktopBackgroundBlurView else { return }
        guard UserDefaults.standard.object(forKey: "clipboardShelfVisible") as? Bool ?? true else {
            background.hideClotheslines()
            return
        }
        let fullScreen = UserDefaults.standard.bool(forKey: "clipboardShelfFullScreen")
        let shelf = ClipboardShelfView(history: model.clipboardHistory, canvasClotheslineMode: !fullScreen, showsRowControls: false,
            onAddToCanvas: { [weak model] item in
                guard let model, let groupID = model.selectedGroupID else { return }
                model.addClipboardItem(item, to: groupID)
            }, onClose: { [weak model] in
                guard let model, model.isDesktopDisplayOn else { return }
                model.toggleDesktopDisplay()
            })
        model.clipboardHistory.start()
        let layout = DesktopOverlayLayout(visibleFrame: screen.visibleFrame, expanded: true,
            fullScreen: fullScreen,
            fullWidth: UserDefaults.standard.bool(forKey: "clipboardShelfFullWidth"),
            shelfHeight: clotheslineHeight)
        // Both the clotheslines and connection drawing belong to the same desktop surface.
        let localFrame = layout.shelf.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        background.showClotheslines(shelf, frame: localFrame)
        if fullScreen {
            panels.values.forEach { $0.orderOut(nil) }
        }
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
    var onClipboardDrop: ((ClipboardCanvasTransfer, CGPoint) -> Bool)?
    let effect = NSVisualEffectView(frame: .zero)
    let tint = NSView(frame: .zero)
    private let dimming = NSView(frame: .zero)
    let connections = DesktopConnectionView(frame: .zero)
    private var clotheslines: DesktopClipboardHostingView?

    func showClotheslines(_ view: ClipboardShelfView, frame: CGRect) {
        if let clotheslines {
            clotheslines.rootView = view
            clotheslines.frame = frame
            clotheslines.isHidden = false
        } else {
            let hosting = DesktopClipboardHostingView(rootView: view)
            hosting.sizingOptions = []
            hosting.frame = frame
            addSubview(hosting)
            clotheslines = hosting
        }
    }

    func hideClotheslines() {
        clotheslines?.isHidden = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onClipboardDrop == nil ? [] : .copy
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { onClipboardDrop != nil }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let data = sender.draggingPasteboard.data(forType: NSPasteboard.PasteboardType(UTType.projectCanvasClipboard.identifier)),
              let item = try? JSONDecoder().decode(ClipboardCanvasTransfer.self, from: data),
              let window else { return false }
        return onClipboardDrop?(item, window.convertPoint(toScreen: sender.draggingLocation)) ?? false
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Decorations share one dismiss target; card windows remain above this background.
        guard !isHidden, alphaValue > 0, frame.contains(point) else { return nil }
        let localPoint = convert(point, from: superview)
        if let clotheslines, !clotheslines.isHidden, clotheslines.frame.contains(localPoint) {
            return clotheslines.hitTest(localPoint) ?? clotheslines
        }
        return self
    }

    override func mouseUp(with event: NSEvent) { onDismiss?() }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.projectCanvasClipboard.identifier)])
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = true
        dimming.wantsLayer = true
        tint.wantsLayer = true
        for view in [effect, tint, dimming, connections] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    func update(appearance: DesktopAppearance) {
        // Blend the native material independently so lines never fade with the blur.
        effect.alphaValue = appearance.blur
        effect.isHidden = appearance.blur == 0
        tint.layer?.backgroundColor = appearance.tintColor.nsColor.withAlphaComponent(appearance.tintOpacity).cgColor
        dimming.layer?.backgroundColor = NSColor.black.withAlphaComponent(appearance.dimming).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

final class DesktopProjectCardView: NSView {
    static let size = CGSize(width: 210, height: 100)

    private var clipboard: CanvasClipboardContent?
    private var previewImage: NSImage?
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

    func update(title: String, color: NSColor, clipboard: CanvasClipboardContent? = nil) {
        guard self.title != title || !self.color.isEqual(color) || self.clipboard != clipboard else { return }
        self.clipboard = clipboard
        previewImage = clipboard?.previewImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
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

        if let image = previewImage, image.size.width > 0, image.size.height > 0 {
            let area = bounds.insetBy(dx: 10, dy: 10)
            let scale = min(area.width / image.size.width, area.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2, width: size.width, height: size.height),
                       from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
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
