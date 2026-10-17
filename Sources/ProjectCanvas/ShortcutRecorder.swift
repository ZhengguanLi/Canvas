import AppKit
import SwiftUI

/// Click, then press a combination with ⌘, ⌃ or ⌥. Escape cancels.
struct ShortcutRecorder: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject private var status = HotKeyStatus.shared
    private var shortcut: HotKeyShortcut { status.shortcut }
    @State private var monitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.tr("显示或隐藏桌面卡片"))
                Spacer()
                Button(status.isRecording ? L10n.tr("按下快捷键…") : shortcut.displayString) {
                    status.isRecording ? stop() : start()
                }
                .font(.body.monospaced())
                .frame(minWidth: 110)
                .buttonStyle(.bordered)
                .tint(status.isRecording ? .accentColor : nil)
                Button(L10n.tr("恢复默认")) { apply(.default) }
                    .disabled(shortcut == .default && !status.isRecording)
            }
            if status.isRecording {
                Text(L10n.tr("需要包含 ⌘、⌃ 或 ⌥。按 Esc 取消。")).font(.caption).foregroundStyle(.secondary)
            } else if status.registrationFailed {
                Label(L10n.format("%@ 可能已被其他应用占用，请换一个快捷键。", shortcut.displayString), systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        status.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // Escape
            if let recorded = HotKeyShortcut.from(keyCode: event.keyCode, modifiers: event.modifierFlags,
                                                  characters: event.charactersIgnoringModifiers) {
                apply(recorded)
            }
            return nil
        }
    }

    private func apply(_ new: HotKeyShortcut) {
        stop()
        status.shortcut = new
        new.save()
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        status.isRecording = false
    }
}
