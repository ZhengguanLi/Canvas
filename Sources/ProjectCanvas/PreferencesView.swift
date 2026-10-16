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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.tr("设置")).font(.title2)
            ScrollView {
                Form {
                    Picker(L10n.tr("语言"), selection: $language.selection) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L10n.tr("默认打开方式"), selection: $model.defaultEditor) {
                        ForEach(EditorChoice.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle(L10n.tr("编辑器默认使用新窗口"), isOn: $model.defaultOpenInNewWindow)
                    Text(L10n.tr("新窗口 / 复用窗口适用于 VS Code 和 Cursor；其他应用使用自身窗口偏好。项目可单独覆盖默认设置。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Picker(L10n.tr("桌面显示"), selection: Binding(get: { model.desktopDisplayMode }, set: model.setDesktopDisplayMode)) {
                        ForEach(DesktopDisplayMode.allCases) { Text($0.title).tag($0) }
                    }
                    Picker(L10n.tr("显示器"), selection: $screenID) {
                        Text(L10n.tr("当前显示器")).tag("")
                        ForEach(NSScreen.screens, id: \.self) { screen in
                            Text(screen.localizedName).tag(DesktopPreferences.identifier(for: screen))
                        }
                    }
                    Text(L10n.tr("应用快捷键：⌘⇧空格，显示或隐藏卡片、连线与模糊背景。前置覆盖模式下，成功打开项目后自动收起。Fn-F11 仅执行 macOS 原生“显示桌面”。"))
                        .font(.caption).foregroundStyle(.secondary)
                    Section(L10n.tr("桌面外观")) {
                    Text(L10n.tr("拖动桌面卡片可调整并保存布局。Esc 取消拖动，再按一次收起；未拖动时直接收起。"))
                        .font(.caption).foregroundStyle(.secondary)
                        Slider(value: $blur, in: 0...1) { Text(L10n.tr("模糊背景强度")) }
                        Slider(value: $dimming, in: 0...0.8) { Text(L10n.tr("背景暗度")) }
                        Slider(value: $cardScale, in: 0.6...1.5) { Text(L10n.tr("卡片大小")) }
                        Text(L10n.format("%d%% · 内容较多时会自动缩小以适应屏幕。", Int(cardScale * 100)))
                            .font(.caption).foregroundStyle(.secondary)
                        Toggle(L10n.tr("显示连线标签"), isOn: $showsLabels)
                        Button(L10n.tr("恢复默认外观")) { blur = 1; dimming = 0; cardScale = 1; showsLabels = true }
                    }
                }
            }
            HStack { Spacer(); Button(L10n.tr("完成")) { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 560, height: 600)
        .onChange(of: screenID) { _, _ in NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil) }
        .onChange(of: blur) { _, _ in refreshDesktop() }
        .onChange(of: dimming) { _, _ in refreshDesktop() }
        .onChange(of: cardScale) { _, _ in refreshDesktop() }
        .onChange(of: showsLabels) { _, _ in refreshDesktop() }
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
