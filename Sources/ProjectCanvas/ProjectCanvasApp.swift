import AppKit
import SwiftUI

@main
struct ProjectCanvasApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var language = LanguageController.shared

    init() {
        BackgroundTint.migrateLegacyPreferences()
    }

    private static var isEditingText: Bool { NSApp.keyWindow?.firstResponder is NSTextView }

    var body: some Scene {
        WindowGroup("ProjectCanvas") {
            MainWindow(model: model)
                .environment(\.locale, language.locale)
                .environmentObject(language)
                .background(WindowMinimumSize(size: CGSize(width: 900, height: 600)))
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            // Format ▸ Font, so ⌘B / ⌘I style text in rich note editors.
            TextFormattingCommands()
            CommandGroup(replacing: .undoRedo) {
                // While text is being edited (a note, a rename field) undo belongs to that text.
                Button(L10n.tr("撤销")) {
                    if Self.isEditingText { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) } else { model.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)
                Button(L10n.tr("重做")) {
                    if Self.isEditingText { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) } else { model.redo() }
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
    }
}

/// The window minimum lives in AppKit: SwiftUI's `.frame(minWidth:minHeight:)` was not enforced on
/// resize (clipping the sidebar footer) and left the split view short of the window bottom.
private struct WindowMinimumSize: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { Probe(size: size) }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class Probe: NSView {
        let size: CGSize
        init(size: CGSize) { self.size = size; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.contentMinSize = size
            let current = window.contentRect(forFrameRect: window.frame).size
            guard current.width < size.width || current.height < size.height else { return }
            var frame = window.frameRect(forContentRect: NSRect(origin: .zero,
                size: CGSize(width: max(current.width, size.width), height: max(current.height, size.height))))
            frame.origin = CGPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
            window.setFrame(frame, display: true)
        }
    }
}
