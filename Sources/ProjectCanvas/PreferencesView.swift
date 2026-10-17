import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("desktopScreenID") private var screenID = ""
    @AppStorage("desktopBlur") private var blur = 1.0
    @AppStorage("desktopDimming") private var dimming = 0.0
    @AppStorage("desktopCardScale") private var cardScale = 1.0
    @AppStorage("desktopLabels") private var showsLabels = true
    @AppStorage(BackgroundTint.colorPreferenceKey) private var tintColor = BackgroundTintColor.default.hex
    @AppStorage(BackgroundTint.opacityPreferenceKey) private var tintOpacity = 0.0

    private enum Page: String, CaseIterable, Identifiable {
        case general, clipboard, desktop
        var id: Self { self }
        var title: String {
            switch self {
            case .general: L10n.tr("通用")
            case .clipboard: L10n.tr("剪贴板")
            case .desktop: L10n.tr("桌面")
            }
        }
    }

    @State private var page = Page.general

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text(L10n.tr("设置")).font(.title2.weight(.semibold))
                Picker(L10n.tr("设置"), selection: $page) {
                    ForEach(Page.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(24)
            Form {
                switch page {
                case .general: generalSettings
                case .clipboard: clipboardSettings
                case .desktop: desktopSettings
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button(L10n.tr("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .frame(width: 640, height: 660)
        .onChange(of: screenID) { _, _ in NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil) }
        .onChange(of: blur) { _, _ in refreshDesktop() }
        .onChange(of: dimming) { _, _ in refreshDesktop() }
        .onChange(of: cardScale) { _, _ in refreshDesktop() }
        .onChange(of: showsLabels) { _, _ in refreshDesktop() }
        .onChange(of: tintColor) { _, _ in refreshDesktop() }
        .onChange(of: tintOpacity) { _, _ in refreshDesktop() }
    }

    @ViewBuilder
    private var generalSettings: some View {
        Section(L10n.tr("语言")) {
            Picker(L10n.tr("语言"), selection: $language.selection) {
                ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
            }
        }
        Section(L10n.tr("打开项目")) {
            Picker(L10n.tr("默认打开方式"), selection: $model.defaultEditor) {
                ForEach(EditorChoice.allCases) { Text($0.title).tag($0) }
            }
            Toggle(L10n.tr("编辑器默认使用新窗口"), isOn: $model.defaultOpenInNewWindow)
            explanation("新窗口 / 复用窗口适用于 VS Code 和 Cursor；其他应用使用自身窗口偏好。项目可单独覆盖默认设置。")
        }
    }

    @ViewBuilder
    private var clipboardSettings: some View {
        Section(L10n.tr("剪贴板显示")) {
            ClipboardDisplayMenu()
        }
        Section(L10n.tr("历史数量上限")) {
            ClipboardHistoryLimitControls(history: model.clipboardHistory, showsHeading: false)
        }
    }

    @ViewBuilder
    private var desktopSettings: some View {
        Section(L10n.tr("桌面显示")) {
            Picker(L10n.tr("桌面显示"), selection: Binding(get: { model.desktopDisplayMode }, set: model.setDesktopDisplayMode)) {
                ForEach(DesktopDisplayMode.allCases) { Text($0.title).tag($0) }
            }
            Picker(L10n.tr("显示器"), selection: $screenID) {
                Text(L10n.tr("当前显示器")).tag("")
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(DesktopPreferences.identifier(for: screen))
                }
            }
            ShortcutRecorder()
            explanation("全局快捷键可显示或隐藏卡片、连线与模糊背景。前置覆盖模式下，成功打开项目后自动收起。Fn-F11 仅执行 macOS 原生“显示桌面”。")
        }
        Section(L10n.tr("桌面外观")) {
            appearanceSlider("模糊背景强度", value: $blur, range: 0...1)
            appearanceSlider("背景暗度", value: $dimming, range: 0...0.8)
            appearanceSlider("卡片大小", value: $cardScale, range: 0.6...1.5)
            explanation("内容较多时会自动缩小以适应屏幕。")
            Toggle(L10n.tr("显示连线标签"), isOn: $showsLabels)
        }
        Section(L10n.tr("磨砂背景颜色")) {
            BackgroundTintControls(colorHex: $tintColor, opacity: $tintOpacity)
            explanation("颜色和浓度同时应用于内容区与桌面磨砂背景。")
        }
        Section {
            explanation("拖动桌面卡片可调整并保存布局。Esc 取消拖动，再按一次收起；未拖动时直接收起。")
            Button(L10n.tr("恢复默认外观")) {
                blur = 1; dimming = 0; cardScale = 1; showsLabels = true
                tintColor = BackgroundTintColor.default.hex; tintOpacity = 0
            }
        }
    }

    private func explanation(_ text: String) -> some View {
        Text(L10n.tr(text)).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func appearanceSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(L10n.tr(title)) {
            HStack(spacing: 12) {
                Slider(value: value, in: range).labelsHidden().accessibilityLabel(L10n.tr(title))
                    .frame(width: 200)
                Text("\(Int(value.wrappedValue * 100))%")
                    .monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        }
    }

    private func refreshDesktop() {
        NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
    }
}

struct ProjectOpeningView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var editor = ""
    @State private var windowMode = "default"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.format("%@ · 打开方式", project.folderName)).font(.headline)
            Picker(L10n.tr("应用"), selection: $editor) {
                Text(L10n.format("跟随默认（%@）", model.defaultEditor.title)).tag("")
                ForEach(EditorChoice.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Picker(L10n.tr("窗口"), selection: $windowMode) {
                Text(L10n.tr("跟随默认")).tag("default")
                Text(L10n.tr("新窗口")).tag("new")
                Text(L10n.tr("复用窗口")).tag("reuse")
            }
            Text(L10n.tr("窗口选项适用于 VS Code / Cursor。设置在所有组中共享。")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer(); Button(L10n.tr("取消")) { dismiss() }
                Button(L10n.tr("保存")) {
                    model.setProjectOpening(project.id, editor: EditorChoice(rawValue: editor), newWindow: windowMode == "default" ? nil : windowMode == "new")
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 450)
        .onAppear { editor = project.editor?.rawValue ?? ""; windowMode = project.openInNewWindow.map { $0 ? "new" : "reuse" } ?? "default" }
    }
}

struct ConnectionEditor: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let groupID: UUID
    let connection: ProjectConnection
    @Environment(\.dismiss) private var dismiss
    @State private var kind = ConnectionKind.dependency
    @State private var label = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.tr("连线属性")).font(.headline)
            Text(L10n.tr("方向：先选的卡片 → 后选的卡片")).font(.caption).foregroundStyle(.secondary)
            Picker(L10n.tr("关系类型"), selection: $kind) { ForEach(ConnectionKind.allCases) { Text($0.title).tag($0) } }
            TextField(L10n.tr("标签（可选，最多 120 字）"), text: $label)
            HStack {
                Spacer(); Button(L10n.tr("取消")) { dismiss() }
                Button(L10n.tr("保存")) { model.updateConnection(connection.id, in: groupID, kind: kind, label: label); dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 420)
        .onAppear { kind = connection.kind; label = connection.label ?? "" }
    }
}

struct ImportCanvasView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var source = ""
    @State private var target = ""
    @State private var file: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("导入项目组")).font(.title2)
            Button(file?.lastPathComponent ?? L10n.tr("选择导出的 JSON 文件…")) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
                if panel.runModal() == .OK { file = panel.url }
            }
            Text(L10n.tr("换电脑时可替换路径前缀；留空保留原路径。导入会新增组，不覆盖已有组。")).font(.caption).foregroundStyle(.secondary)
            TextField(L10n.tr("原路径前缀，例如 /Users/old/Code"), text: $source)
            TextField(L10n.tr("新路径前缀，例如 /Users/me/Code"), text: $target)
            if model.needsRecovery { Text(L10n.tr("导入后会恢复保存；原文件将另存保留。")).font(.caption).foregroundStyle(.orange) }
            HStack {
                Spacer(); Button(L10n.tr("取消")) { dismiss() }
                Button(L10n.tr("导入")) {
                    if let file { model.importGroups(from: file, pathFrom: source, pathTo: target) }
                    dismiss()
                }.disabled(file == nil || (source.isEmpty != target.isEmpty)).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 500)
    }
}
