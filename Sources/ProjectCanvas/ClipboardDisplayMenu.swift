import SwiftUI

func notifyClipboardDisplayChange() {
    NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
}

/// Persistent display choices shared by the main window and desktop overlay.
struct ClipboardDisplayMenu: View {
    @ObservedObject private var language = LanguageController.shared
    @AppStorage("clipboardShelfVisible") private var visible = true
    @AppStorage("clipboardShelfFullWidth") private var fullWidth = false
    @AppStorage("clipboardShelfFullScreen") private var fullScreen = false

    private var selection: Binding<Int> {
        Binding(get: { visible ? (fullWidth ? 1 : 0) : 2 }, set: { value in
            visible = value != 2
            if value != 2 { fullWidth = value == 1 }
            fullScreen = false
            notifyClipboardDisplayChange()
        })
    }

    var body: some View {
        Menu {
            Picker(L10n.tr("剪贴板显示"), selection: selection) {
                Text(L10n.tr("默认宽度")).tag(0)
                Text(L10n.tr("左右展开")).tag(1)
                Text(L10n.tr("不展示")).tag(2)
            }
        } label: {
            Label(L10n.tr("剪贴板显示"), systemImage: "clipboard")
        }.help(L10n.tr("剪贴板显示"))
    }
}
