import AppKit
import SwiftUI

extension CardColor {
    var nsColor: NSColor {
        switch self {
        case .neutral: return .windowBackgroundColor
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .orange: return .systemOrange
        case .pink: return .systemPink
        case .purple: return .systemPurple
        }
    }

    /// Opaque card colour: 20% of the hue mixed into the window colour, resolved per appearance,
    /// so a tinted canvas never shows through.
    var fill: Color {
        let base = Color(nsColor: .windowBackgroundColor)
        return self == .neutral ? base : base.mix(with: Color(nsColor: nsColor), by: 0.2)
    }

    /// Translucent wash for areas that should let the canvas show through, such as regions.
    var wash: Color {
        self == .neutral ? Color.secondary.opacity(0.2) : Color(nsColor: nsColor).opacity(0.2)
    }
}

/// A native scrolling host preserves the viewport independently for each group.
struct CanvasScrollView<Content: View>: NSViewRepresentable {
    let size: CGSize
    @Binding var offset: CGPoint
    var onViewportCommit: (CGPoint) -> Void = { _ in }
    @ViewBuilder var content: () -> Content

    func makeCoordinator() -> Coordinator { Coordinator(offset: $offset, onViewportCommit: onViewportCommit) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let host = NSHostingView(rootView: content())
        host.sizingOptions = []
        scroll.documentView = host
        context.coordinator.host = host
        scroll.contentView.postsBoundsChangedNotifications = true
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak coordinator = context.coordinator, weak scroll] _ in
            guard let coordinator, let scroll, !coordinator.updating else { return }
            coordinator.pending?.cancel()
            let position = scroll.contentView.bounds.origin
            coordinator.pendingPosition = position
            let work = DispatchWorkItem { [weak coordinator] in
                guard let coordinator else { return }
                coordinator.pendingPosition = nil
                coordinator.offset.wrappedValue = position
                coordinator.onViewportCommit(position)
            }
            coordinator.pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.offset = $offset
        coordinator.onViewportCommit = onViewportCommit
        coordinator.updating = true
        coordinator.host?.rootView = content()
        coordinator.host?.setFrameSize(size)
        if coordinator.lastRequested != offset {
            coordinator.pending?.cancel()
            coordinator.pendingPosition = nil
            scroll.contentView.scroll(to: offset)
            scroll.reflectScrolledClipView(scroll.contentView)
            coordinator.lastRequested = offset
        }
        coordinator.updating = false
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.pending?.cancel()
        coordinator.pending = nil
        if let position = coordinator.pendingPosition {
            // Persist by group identity: the SwiftUI state binding is already being torn down.
            // Defer publication until the current view update has completed.
            let commit = coordinator.onViewportCommit
            DispatchQueue.main.async { commit(position) }
            coordinator.pendingPosition = nil
        }
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        coordinator.observer = nil
        coordinator.host = nil
        scroll.documentView = nil
    }

    final class Coordinator {
        var offset: Binding<CGPoint>
        var host: NSHostingView<Content>?
        var observer: NSObjectProtocol?
        var updating = false
        var lastRequested: CGPoint?
        var pending: DispatchWorkItem?
        var pendingPosition: CGPoint?
        var onViewportCommit: (CGPoint) -> Void
        init(offset: Binding<CGPoint>, onViewportCommit: @escaping (CGPoint) -> Void) {
            self.offset = offset
            self.onViewportCommit = onViewportCommit
        }
        deinit {
            pending?.cancel()
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
