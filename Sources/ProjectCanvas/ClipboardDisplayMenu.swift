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

/// Background for clipboard text cards; follows All Cards Background unless a color is chosen.
struct ClipboardTextColorMenu: View {
    @ObservedObject private var language = LanguageController.shared
    @AppStorage(ClipboardAppearance.textColorKey) private var choice = ClipboardAppearance.followCardsColor

    var body: some View {
        Menu(L10n.tr("剪贴板文字背景")) {
            Picker(L10n.tr("剪贴板文字背景"), selection: $choice) {
                Text(L10n.tr("跟随所有卡片背景")).tag(ClipboardAppearance.followCardsColor)
                Divider()
                ForEach(CardColor.allCases) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.inline).labelsHidden()
        }
    }
}
