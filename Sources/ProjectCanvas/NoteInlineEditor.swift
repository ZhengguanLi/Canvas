import SwiftUI

/// Rich text editing directly on a note card. Format ▸ Font (⌘B, ⌘I) styles the selection;
/// leaving the editor, Escape or ⌘Return saves.
struct NoteInlineEditor: View {
    @Binding var text: AttributedString
    let onCommit: () -> Void
    @AppStorage(ClipboardAppearance.textSizeKey) private var textSize = 14.0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(L10n.tr("便签"), systemImage: "note.text").font(.caption2).foregroundStyle(.secondary)
            TextEditor(text: $text)
                .font(.system(size: ClipboardAppearance(textSize: textSize).textSize))
                .scrollContentBackground(.hidden)
                .focused($focused)
            Text(L10n.tr("⌘B 粗体 · ⌘I 斜体 · Esc 完成")).font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(9)
        .frame(width: 280, height: 180)
        .onAppear { focused = true }
        .onChange(of: focused) { _, isFocused in if !isFocused { onCommit() } }
        .onExitCommand(perform: onCommit)
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            onCommit()
            return .handled
        }
    }
}
