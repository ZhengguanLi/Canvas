import AppKit
import SwiftUI

/// Keeps canvas shortcuts local and lets Control-click extend selection on macOS.
struct CanvasInputSupport: NSViewRepresentable {
    enum Direction { case left, right, up, down }
    enum Key: Equatable { case arrow(Direction), open, duplicate }

    let onSelectAll: () -> Void
    /// Returns true when the key was handled, so it does not also scroll the canvas.
    var onKey: (Key) -> Bool = { _ in false }

    static func key(for event: NSEvent) -> Key? {
        guard event.type == .keyDown else { return nil }
        let flags = event.modifierFlags.intersection([.control, .command, .shift, .option])
        if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "d" { return .duplicate }
        guard flags.isEmpty else { return nil }
        switch event.keyCode {
        case 123: return .arrow(.left)
        case 124: return .arrow(.right)
        case 125: return .arrow(.down)
        case 126: return .arrow(.up)
        case 36, 76: return .open
        default: return nil
        }
    }

    static func extendsSelection(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.control, .shift]).isEmpty
    }

    /// Flags of the click being handled. The global `NSEvent.modifierFlags` reflects key state at
    /// read time, which can miss a modifier carried only by the (normalized) mouse event.
    static var currentEventExtendsSelection: Bool {
        extendsSelection(NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags)
    }

    static func isSelectAll(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.control, .command, .shift, .option])
        return event.type == .keyDown && event.charactersIgnoringModifiers?.lowercased() == "a" &&
            (flags == .control || flags == .command)
    }

    static func normalizedMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard [.leftMouseDown, .leftMouseUp, .leftMouseDragged].contains(event.type),
              event.modifierFlags.contains(.control) else { return event }
        // Native Control-click otherwise opens a context menu before SwiftUI sees the tap.
        return NSEvent.mouseEvent(with: event.type, location: event.locationInWindow,
            modifierFlags: event.modifierFlags.subtracting(.control).union(.shift), timestamp: event.timestamp,
            windowNumber: event.windowNumber, context: nil, eventNumber: event.eventNumber,
            clickCount: event.clickCount, pressure: event.pressure)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.view = view
        context.coordinator.onSelectAll = onSelectAll
        context.coordinator.onKey = onKey
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onSelectAll = onSelectAll
        context.coordinator.onKey = onKey
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        weak var view: NSView?
        var onSelectAll: (() -> Void)?
        var onKey: ((Key) -> Bool)?
        private var monitor: Any?

        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .leftMouseUp, .leftMouseDragged]) { [weak self] event in
                guard let self, let view = self.view, let window = view.window,
                      event.window === window, !view.isHiddenOrHasHiddenAncestor,
                      window.attachedSheet == nil else { return event }
                if Self.isEditingText(in: window) { return event }
                if CanvasInputSupport.isSelectAll(event) {
                    self.onSelectAll?()
                    return nil
                }
                if let key = CanvasInputSupport.key(for: event), self.onKey?(key) == true { return nil }
                guard event.type != .keyDown,
                      view.visibleRect.contains(view.convert(event.locationInWindow, from: nil)) else { return event }
                return CanvasInputSupport.normalizedMouseEvent(event) ?? event
            }
        }

        private static func isEditingText(in window: NSWindow) -> Bool {
            window.firstResponder is NSTextView || window.firstResponder is NSTextField
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stop() }
    }
}
