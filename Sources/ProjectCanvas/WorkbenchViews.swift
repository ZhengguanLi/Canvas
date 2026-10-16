import AppKit
import SwiftUI

struct GlobalSearchView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedID: String?
    @FocusState private var searchFocused: Bool
    private var results: [ProjectSearchResult] { model.searchProjects(query) }
    private var selected: ProjectSearchResult? { results.first { $0.id == selectedID } ?? results.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("搜索所有项目组")).font(.headline)
            TextField(L10n.tr("项目名称、路径或标签"), text: $query).textFieldStyle(.roundedBorder).focused($searchFocused)
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onSubmit { open() }
            List(selection: $selectedID) {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(result.card.customName ?? result.project.folderName).fontWeight(.medium)
                        Text(result.groupName + " · " + result.project.folderPath).font(.caption).foregroundStyle(.secondary)
                    }.tag(result.id)
                }
            }
            if results.isEmpty { Text(L10n.tr("没有匹配的项目")).foregroundStyle(.secondary) }
            HStack {
                Text(L10n.tr("↑↓ 选择 · 回车打开 · ⌘回车定位")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L10n.tr("取消"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("打开项目"), action: open).keyboardShortcut(.defaultAction).disabled(selected == nil)
                Button(L10n.tr("定位到画布"), action: locate).keyboardShortcut(.return, modifiers: .command).disabled(selected == nil)
            }
        }.padding(20).frame(width: 700, height: 450)
            .onAppear { searchFocused = true; selectedID = results.first?.id }
            .onChange(of: query) { _, _ in selectedID = results.first?.id }
    }

    private func moveSelection(_ delta: Int) {
        guard !results.isEmpty else { return }
        let index = results.firstIndex { $0.id == selectedID } ?? 0
        selectedID = results[min(results.count - 1, max(0, index + delta))].id
    }
    private func open() { if let selected { model.openProject(selected.project); dismiss() } }
    private func locate() { if let selected { model.locate(selected); dismiss() } }
}

struct ProjectDetailsView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var links: [ProjectLink]
    @State private var tags: String
    @State private var configurations: [LaunchConfiguration]
    @State private var editingConfiguration: LaunchConfiguration?
    @State private var error: String?

    init(model: AppModel, project: Project) {
        self.model = model; self.project = project
        _notes = State(initialValue: project.notes ?? "")
        _links = State(initialValue: project.links ?? [])
        _tags = State(initialValue: project.tags.joined(separator: ", "))
        _configurations = State(initialValue: project.launchConfigurations)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(project.folderName).font(.title2)
            Text(L10n.tr("项目详情（所有项目组共享）")).foregroundStyle(.secondary)
            TabView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(L10n.tr("标签（用逗号分隔）"), text: $tags).textFieldStyle(.roundedBorder)
                    TextEditor(text: $notes).font(.body).border(.quaternary).frame(minHeight: 160).accessibilityLabel(L10n.tr("项目备注"))
                    HStack {
                        Text(L10n.tr("链接")).font(.headline)
                        Spacer()
                        Button(L10n.tr("添加链接")) { links.append(ProjectLink(name: "", address: "https://")) }
                    }
                    ScrollView {
                        VStack {
                            ForEach($links) { $link in
                                HStack {
                                    TextField(L10n.tr("名称"), text: $link.name).frame(width: 130)
                                    TextField("https://…", text: $link.address)
                                    Button { if let url = link.validatedURL { NSWorkspace.shared.open(url) } } label: { Image(systemName: "arrow.up.right.square") }.disabled(link.validatedURL == nil).help(L10n.tr("打开链接"))
                                    Button { links.removeAll { $0.id == link.id } } label: { Image(systemName: "minus.circle") }.help(L10n.tr("移除链接"))
                                }
                            }
                        }
                    }.frame(height: 150)
                }.padding(12).tabItem { Text(L10n.tr("备注与标签")) }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(L10n.tr("在 Terminal 中运行，工作目录默认为项目文件夹。")).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(L10n.tr("添加启动配置")) { editingConfiguration = LaunchConfiguration(name: "", command: "") }
                    }
                    List {
                        ForEach(configurations) { configuration in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(configuration.name).fontWeight(.medium)
                                    Text(configuration.command).font(.caption.monospaced()).lineLimit(2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(L10n.tr("编辑")) { editingConfiguration = configuration }
                                Button(L10n.tr("删除"), role: .destructive) { configurations.removeAll { $0.id == configuration.id } }
                            }
                        }
                    }
                }.padding(12).tabItem { Text(L10n.tr("启动配置")) }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack {
                Spacer()
                Button(L10n.tr("取消"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存")) {
                    guard links.allSatisfy({ $0.validatedURL != nil }) else { error = L10n.tr("链接需要名称和有效的 HTTP 或 HTTPS 地址。"); return }
                    let parsedTags = tags.components(separatedBy: CharacterSet(charactersIn: ",，\n"))
                    if model.saveProjectDetails(project.id, notes: notes, links: links, tags: parsedTags, configurations: configurations) { dismiss() }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 700, height: 570)
            .sheet(item: $editingConfiguration) { configuration in
                LaunchConfigurationEditor(configuration: configuration) { saved in
                    if let index = configurations.firstIndex(where: { $0.id == saved.id }) { configurations[index] = saved }
                    else { configurations.append(saved) }
                }
            }
    }
}

struct RegionEditorView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let groupID: UUID
    let cardIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var color = CardColor.blue
    private let region: ProjectRegion?

    init(model: AppModel, groupID: UUID, cardIDs: Set<UUID>, region: ProjectRegion? = nil) {
        self.model = model; self.groupID = groupID; self.cardIDs = cardIDs; self.region = region
        _name = State(initialValue: region?.name ?? "")
        _color = State(initialValue: region?.color ?? .blue)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(region == nil ? L10n.tr("从选中卡片创建区域") : L10n.tr("编辑区域")).font(.headline)
            TextField(L10n.tr("区域名称"), text: $name)
            Picker(L10n.tr("颜色"), selection: $color) { ForEach(CardColor.allCases) { Text($0.title).tag($0) } }
            Text(L10n.tr("拖动区域标题可一起移动成员；移除区域会保留卡片。")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button(L10n.tr("取消"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("保存")) {
                    if let region { model.updateRegion(region.id, name: name, color: color, in: groupID) }
                    else { model.addRegion(name: name, color: color, cardIDs: cardIDs, in: groupID) }
                    dismiss()
                }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 430)
    }
}

struct LayoutPreviewView: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let preview: LayoutPreview
    @Environment(\.dismiss) private var dismiss
    private var group: ProjectGroup { preview.proposed }
    private var isStale: Bool { model.groups.first(where: { $0.id == preview.original.id }) != preview.original }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.tr("布局预览")).font(.title2)
            Text(L10n.tr("当前手动布局保持不变。只有点击应用后才会保存，可一次撤销。")).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let extent = CanvasGeometry.extent(cards: group.cards)
                let scale = min(1, min(geometry.size.width / extent.width, geometry.size.height / extent.height))
                CanvasBoard(model: model, group: group, zoom: scale, isEditing: false, snapToGrid: false,
                            selectedCardIDs: .constant([]), selectedConnectionID: .constant(nil),
                            isConnecting: .constant(false), firstConnectionCardID: .constant(nil),
                            highlightDirection: 0, onOpenSettings: { _ in }, onRelocate: { _ in })
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }.clipped().background(Color(nsColor: .textBackgroundColor))
            if isStale {
                Text(L10n.tr("画布已更改，请重新生成布局预览。")).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button(L10n.tr("取消"), role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(L10n.tr("应用布局")) { if model.applyLayout(preview) { dismiss() } }.keyboardShortcut(.defaultAction).disabled(isStale)
            }
        }.padding(20).frame(width: 850, height: 590)
    }
}
