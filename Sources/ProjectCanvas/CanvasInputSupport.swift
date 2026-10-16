import AppKit
import SwiftUI

/// Keeps canvas shortcuts local and lets Control-click extend selection on macOS.
struct CanvasInputSupport: NSViewRepresentable {
    let onSelectAll: () -> Void

    static func extendsSelection(_ flags: NSEvent.ModifierFlags) -> Bool {
        !flags.intersection([.control, .shift]).isEmpty
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
        context.coordinator.start()
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onSelectAll = onSelectAll
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator {
        weak var view: NSView?
        var onSelectAll: (() -> Void)?
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
