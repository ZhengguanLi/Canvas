import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    @State private var showsSearch = false
    @State private var showsSettings = false
    @State private var showsImport = false
    @State private var confirmsRestore = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                if model.needsRecovery {
                    HStack {
                        Label(L10n.tr("原数据无法读取，保存已暂停。可恢复备份或导入已导出的数据。"), systemImage: "exclamationmark.triangle")
                        Button(L10n.tr("恢复备份")) { confirmsRestore = true }
                        Button(L10n.tr("导入…")) { showsImport = true }
                    }.font(.caption).padding(10).background(.orange.opacity(0.15))
                }
                if let group = model.selectedGroup {
                    GroupWorkspace(model: model, group: group).id(group.id)
                } else { ContentUnavailableView(L10n.tr("还没有项目组"), systemImage: "square.grid.2x2") }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.restoreDesktopDisplayIfNeeded(); model.clipboardHistory.start() }
        .task {
            while !Task.isCancelled {
                await model.refreshGitStatuses()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refreshGitStatuses() }
        }
        .sheet(isPresented: $showsSearch) { GlobalSearchView(model: model) }
        .sheet(item: $model.layoutPreview) { LayoutPreviewView(model: model, preview: $0) }
        .sheet(isPresented: $showsSettings) { PreferencesView(model: model) }
        .sheet(isPresented: $showsImport) { ImportCanvasView(model: model) }
        .confirmationDialog(L10n.tr("恢复最近的有效备份？当前文件会另存保留。"), isPresented: $confirmsRestore) {
            Button(L10n.tr("恢复备份")) { model.restoreBackup() }
        }
        .alert(L10n.tr("重命名"), isPresented: $model.isEditingName) {
            TextField(L10n.tr("名称"), text: $model.nameDraft)
            Button(L10n.tr("取消"), role: .cancel) { }
            Button(L10n.tr("保存")) { model.saveName() }
        }
        .alert("ProjectCanvas", isPresented: Binding(get: { model.alertMessage != nil }, set: { if !$0 { model.alertMessage = nil } })) {
            Button(L10n.tr("好")) { model.alertMessage = nil }
        } message: { Text(model.alertMessage ?? "") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("项目组")).font(.headline)
                Spacer()
                Button(action: model.addGroup) { Image(systemName: "plus") }.help(L10n.tr("新建项目组"))
            }.padding(.horizontal, 14).padding(.top, 18)
            Button { showsSearch = true } label: { Label(L10n.tr("搜索项目"), systemImage: "magnifyingglass") }.keyboardShortcut("k", modifiers: .command).padding(.horizontal, 14)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.groups) { group in
                        Button { model.selectedGroupID = group.id } label: {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                Text(group.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Text("\(group.cards.count)").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(10)
                            .background(model.selectedGroupID == group.id ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(L10n.tr("重命名")) { model.beginRenaming(groupID: group.id) }
                            Button(L10n.tr("导出项目组…")) { exportGroup(group.id) }
                            Button(L10n.tr("删除项目组"), role: .destructive) { model.deleteGroup(group.id) }
                        }
                    }
                }.padding(.horizontal, 8)
            }
            Spacer(minLength: 0)
            Menu {
                Button(L10n.tr("导入项目组…")) { showsImport = true }
                Button(L10n.tr("导出当前项目组…")) { if let id = model.selectedGroupID { exportGroup(id) } }
                Button(L10n.tr("从最近备份恢复…")) { confirmsRestore = true }
            } label: { Label(L10n.tr("导入、导出与恢复"), systemImage: "externaldrive") }
            .padding(.horizontal, 12)
            Button { showsSettings = true } label: { Label(L10n.tr("设置"), systemImage: "gearshape") }
                .keyboardShortcut(",", modifiers: .command).padding(.horizontal, 12)
            Text(L10n.tr("数据保存在这台 Mac 上\n⌘⇧空格 呼出/收起桌面卡片"))
                .font(.caption2).foregroundStyle(.secondary).padding(12)
        }
        .frame(width: 200)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func exportGroup(_ id: UUID) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ProjectCanvas-group.json"
        if panel.runModal() == .OK, let url = panel.url { model.exportGroup(id, to: url) }
    }
}

private struct GroupWorkspace: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let group: ProjectGroup
    @State private var isEditing = false
    @State private var snapToGrid = true
    @State private var isConnecting = false
    @State private var zoom = 1.0
    @State private var offset = CGPoint.zero
    @State private var firstConnectionCardID: UUID?
    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedConnectionID: UUID?
    @State private var highlightDirection = 0
    @State private var projectToConfigure: Project?
    @State private var connectionToConfigure: ProjectConnection?
    @State private var showsRegionEditor = false
    @State private var projectDetails: Project?
    @State private var loadedViewport = false
    @State private var pinchStart: Double?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if isEditing { editingToolbar }
            GeometryReader { geometry in
                ZStack {
                    let size = CanvasGeometry.extent(cards: group.cards)
                    CanvasScrollView(size: CGSize(width: max(geometry.size.width, size.width * zoom), height: max(geometry.size.height, size.height * zoom)), offset: $offset, onViewportCommit: { [zoom] position in
                        model.updateViewport(CanvasViewport(zoom: zoom, offsetX: position.x, offsetY: position.y), in: group.id)
                    }) {
                        CanvasBoard(model: model, group: group, zoom: zoom, isEditing: isEditing, snapToGrid: snapToGrid,
                                    selectedCardIDs: $selectedCardIDs, selectedConnectionID: $selectedConnectionID,
                                    isConnecting: $isConnecting, firstConnectionCardID: $firstConnectionCardID,
                                    highlightDirection: highlightDirection, onOpenSettings: { projectToConfigure = $0 }, onRelocate: relocate, onOpenDetails: { projectDetails = $0 })
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .simultaneousGesture(MagnificationGesture().onChanged { scale in
                        if pinchStart == nil { pinchStart = zoom }
                        zoom = min(2, max(0.1, (pinchStart ?? zoom) * scale))
                    }.onEnded { _ in pinchStart = nil; saveViewport() })
                    .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: dropFolders)
                    if group.cards.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.tr("添加项目文件夹"), systemImage: "folder.badge.plus")
                        } description: { Text(L10n.tr("从 Finder 拖入，或点击下方按钮。")) }
                        actions: { Button(L10n.tr("选择文件夹"), action: chooseFolders) }
                    }
                    VStack {
                        Spacer()
                        HStack {
                            if isConnecting { Text(firstConnectionCardID == nil ? L10n.tr("先点起点，再点终点") : L10n.tr("点击终点完成连线")).font(.caption) }
                            Spacer()
                            Button(L10n.tr("显示全部")) { fit(in: geometry.size) }
                            Button(L10n.tr("回到内容")) {
                                offset = CGPoint(x: max(0, (group.cards.map(\.x).min() ?? 0) - 30) * zoom, y: max(0, (group.cards.map(\.y).min() ?? 0) - 30) * zoom)
                            }
                        }.padding(10).background(.regularMaterial)
                    }
                }
            }
        }
        .onAppear {
            let viewport = group.viewport ?? CanvasViewport()
            zoom = min(2, max(0.1, viewport.zoom))
            offset = CGPoint(x: viewport.offsetX, y: viewport.offsetY)
            loadedViewport = true
            locateRequestedCard()
        }
        .onChange(of: model.locateRequest) { _, _ in locateRequestedCard() }
        .onChange(of: group.viewport) { _, viewport in
            guard let viewport else { return }
            zoom = min(2, max(0.1, viewport.zoom))
            offset = CGPoint(x: viewport.offsetX, y: viewport.offsetY)
        }
        .onChange(of: zoom) { _, _ in saveViewport() }
        .onChange(of: offset) { _, _ in saveViewport() }
        .sheet(isPresented: $showsRegionEditor) { RegionEditorView(model: model, groupID: group.id, cardIDs: selectedCardIDs) }
        .sheet(item: $projectDetails) { ProjectDetailsView(model: model, project: $0) }
        .sheet(item: $projectToConfigure) { ProjectOpeningView(model: model, project: $0) }
        .sheet(item: $connectionToConfigure) { ConnectionEditor(model: model, groupID: group.id, connection: $0) }
        .onExitCommand { isConnecting = false; firstConnectionCardID = nil; selectedCardIDs.removeAll(); selectedConnectionID = nil }
        .onDeleteCommand { deleteSelection() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Text(group.name).font(.headline).lineLimit(1)
            Spacer(minLength: 4)
            Button(action: chooseFolders) { Image(systemName: "folder.badge.plus") }.help(L10n.tr("添加文件夹（⇧⌘O）")).keyboardShortcut("o", modifiers: [.command, .shift])
            Button { model.toggleDesktopDisplay() } label: { Image(systemName: model.isDesktopDisplayOn ? "rectangle.slash" : "menubar.dock.rectangle") }.help(L10n.tr("显示或隐藏桌面卡片（⌘⇧空格）"))
            Button { Task { await model.refreshGitStatuses() } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.isRefreshingGit).help(L10n.tr("刷新 Git 状态"))
            Button {
                isEditing.toggle(); isConnecting = false; firstConnectionCardID = nil; selectedCardIDs.removeAll(); selectedConnectionID = nil
            } label: { Label(isEditing ? L10n.tr("完成") : L10n.tr("编辑"), systemImage: isEditing ? "checkmark" : "pencil") }
            Button { model.undo() } label: { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z", modifiers: .command).disabled(!model.canUndo).help(L10n.tr("撤销"))
            Button { model.redo() } label: { Image(systemName: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!model.canRedo).help(L10n.tr("重做"))
            Divider().frame(height: 20)
            Button { zoom = max(0.1, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass") }
            Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit()).frame(width: 38)
            Button { zoom = min(2, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass") }
        }.controlSize(.small).padding(.horizontal, 14).frame(height: 50)
    }

    private var editingToolbar: some View {
        HStack(spacing: 10) {
            Menu(L10n.tr("布局")) {
                Button(L10n.tr("网格布局预览…")) { model.autoLayoutCards(in: group.id) }
                Button(L10n.tr("关系布局预览…")) { model.layoutPreview = model.makeLayoutPreview(in: group.id, mode: .relationships) }
                Button(L10n.tr("对齐到网格")) { model.alignCardsToGrid(in: group.id) }
                Toggle(L10n.tr("拖动吸附"), isOn: $snapToGrid)
            }
            Button(L10n.tr("创建区域…")) { showsRegionEditor = true }.disabled(selectedCardIDs.isEmpty)
            Menu(L10n.tr("背景颜色")) {
                ForEach(CardColor.allCases) { color in
                    Button(color.title) { model.setCardColor(color, ids: selectedCardIDs, in: group.id) }
                }
            }.disabled(selectedCardIDs.isEmpty)
            Button(isConnecting ? L10n.tr("取消连线") : L10n.tr("连线")) { isConnecting.toggle(); firstConnectionCardID = nil }.disabled(group.cards.count < 2)
            Menu(L10n.tr("关系")) {
                Toggle(L10n.tr("显示连线"), isOn: Binding(get: { group.showsConnections }, set: { _ in model.toggleConnections(for: group.id); selectedConnectionID = nil }))
                Picker(L10n.tr("高亮"), selection: $highlightDirection) {
                    Text(L10n.tr("全部")).tag(0); Text(L10n.tr("选中项目的上游")).tag(-1); Text(L10n.tr("选中项目的下游")).tag(1)
                }
            }
            if let id = selectedConnectionID, let edge = group.connections.first(where: { $0.id == id }) {
                Button(L10n.tr("连线属性")) { connectionToConfigure = edge }
            }
            Spacer(minLength: 0)
            Text(selectedCardIDs.isEmpty ? L10n.tr("拖框选择 · ⇧ 追加") : L10n.format("已选 %d 张", selectedCardIDs.count)).font(.caption).foregroundStyle(.secondary)
            Button(action: deleteSelection) { Image(systemName: "trash") }.disabled(selectedCardIDs.isEmpty && selectedConnectionID == nil).help(L10n.tr("删除选中项"))
        }.controlSize(.small).padding(.horizontal, 14).frame(height: 38).background(.quaternary.opacity(0.3))
    }

    private func locateRequestedCard() {
        guard let request = model.locateRequest, request.groupID == group.id,
              let card = group.cards.first(where: { $0.id == request.cardID }) else { return }
        selectedCardIDs = [card.id]
        zoom = 1
        offset = CGPoint(x: max(0, card.x - 60), y: max(0, card.y - 60))
        model.locateRequest = nil
    }

    private func saveViewport() {
        guard loadedViewport, pinchStart == nil else { return }
        model.updateViewport(CanvasViewport(zoom: zoom, offsetX: offset.x, offsetY: offset.y), in: group.id)
    }

    private func fit(in size: CGSize) {
        let minX = max(0, (group.cards.map(\.x).min() ?? 0) - 30)
        let minY = max(0, (group.cards.map(\.y).min() ?? 0) - 30)
        let width = max(210, (group.cards.map(\.x).max() ?? 0) + 240 - minX)
        let height = max(100, (group.cards.map(\.y).max() ?? 0) + 130 - minY)
        zoom = min(1.5, max(0.1, min(size.width / width, (size.height - 50) / height)))
        offset = CGPoint(x: minX * zoom, y: minY * zoom)
    }

    private func deleteSelection() {
        guard isEditing else { return }
        if let id = selectedConnectionID { model.removeConnection(id, in: group.id); selectedConnectionID = nil }
        model.removeCards(selectedCardIDs, from: group.id)
        selectedCardIDs.removeAll()
    }

    private func chooseFolders() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.addProjects(folderURLs: panel.urls, to: group.id)
            Task { await model.refreshGitStatuses() }
        }
    }

    private func relocate(_ project: Project) {
        let panel = NSOpenPanel(); panel.title = L10n.format("重新定位 %@", project.folderName); panel.canChooseFiles = false; panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { model.relocateProject(project.id, to: url) }
    }

    private func dropFolders(_ providers: [NSItemProvider]) -> Bool {
        let destination = group.id
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            model.addProjects(folderURLs: urls, to: destination)
            await model.refreshGitStatuses()
        }
        return !providers.isEmpty
    }
}
