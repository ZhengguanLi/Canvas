import SwiftUI

struct LaunchConfigurationEditor: View {
    @ObservedObject private var language = LanguageController.shared
    @Environment(\.dismiss) private var dismiss
    @State private var configuration: LaunchConfiguration
    @State private var variables: [EnvironmentEntry]
    @State private var error: String?
    let onSave: (LaunchConfiguration) -> Void

    private struct EnvironmentEntry: Identifiable {
        var id = UUID()
        var key: String
        var value: String
    }

    init(configuration: LaunchConfiguration, onSave: @escaping (LaunchConfiguration) -> Void) {
        _configuration = State(initialValue: configuration)
        _variables = State(initialValue: configuration.environment.sorted { $0.key < $1.key }.map { EnvironmentEntry(key: $0.key, value: $0.value) })
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("启动配置")).font(.title2)
            TextField(L10n.tr("名称"), text: $configuration.name).textFieldStyle(.roundedBorder)
            Text(L10n.tr("命令")).font(.headline)
            TextEditor(text: $configuration.command).font(.body.monospaced()).frame(height: 110).border(.quaternary)
                .accessibilityLabel(L10n.tr("命令"))
            TextField(L10n.tr("工作目录（留空使用项目目录，可填写相对路径）"), text: $configuration.workingDirectory)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text(L10n.tr("环境变量")).font(.headline)
                Spacer()
                Button(L10n.tr("添加变量")) { variables.append(EnvironmentEntry(key: "", value: "")) }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach($variables) { $variable in
                        HStack(alignment: .top) {
                            TextField("KEY", text: $variable.key).frame(width: 160)
                            TextField(L10n.tr("值"), text: $variable.value, axis: .vertical)
                            Button { variables.removeAll { $0.id == variable.id } } label: { Image(systemName: "minus.circle") }
                                .help(L10n.tr("删除"))
                        }.textFieldStyle(.roundedBorder)
                    }
                }
            }.frame(minHeight: 100)
            Text(L10n.tr("命令使用 zsh 执行；环境变量以明文保存在本机项目数据及导出文件中。"))
                .font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button(L10n.tr("取消"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存"), action: save).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 650, height: 510)
    }

    private func save() {
        var saved = configuration
        saved.name = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var environment: [String: String] = [:]
        for variable in variables {
            let key = variable.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, environment[key] == nil else {
                error = L10n.tr("环境变量名称不能为空或重复。"); return
            }
            environment[key] = variable.value
        }
        saved.environment = environment
        guard saved.isValid else { error = L10n.tr("启动配置需要名称、命令和有效的环境变量名称。"); return }
        onSave(saved)
        dismiss()
    }
}

struct ProjectRunMenu: View {
    @ObservedObject var model: AppModel
    let project: Project

    var body: some View {
        if !project.launchConfigurations.isEmpty {
            Menu(L10n.tr("运行")) {
                ForEach(project.launchConfigurations) { configuration in
                    Button(configuration.name) { model.runProject(project, configuration: configuration) }
                }
            }
        }
    }
}

struct ProjectUsageList: View {
    @ObservedObject var model: AppModel
    let results: [ProjectSearchResult]
    let showsCount: Bool

    var body: some View {
        ForEach(Array(results.prefix(8))) { result in
            HStack(spacing: 4) {
                Button { model.openProject(result.project) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.card.customName ?? result.project.folderName).lineLimit(1)
                        if showsCount {
                            Text(L10n.format("打开 %d 次", result.project.openCount)).font(.caption2).foregroundStyle(.secondary)
                        } else if let date = result.project.lastOpenedAt {
                            Text(date, style: .relative).font(.caption2).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).help(result.project.folderPath)
                    .contextMenu {
                        Button(L10n.tr("打开项目")) { model.openProject(result.project) }
                        Button(L10n.tr("定位到画布")) { model.locate(result) }
                        ProjectRunMenu(model: model, project: result.project)
                    }
                Button { model.locate(result) } label: { Image(systemName: "scope") }
                    .buttonStyle(.borderless).help(L10n.tr("定位到画布"))
            }.padding(.vertical, 4)
        }
    }
}
