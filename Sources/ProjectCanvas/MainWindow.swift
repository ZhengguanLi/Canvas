import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MainWindow: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    @AppStorage("clipboardShelfVisible") private var clipboardVisible = true
    @AppStorage("clipboardShelfFullWidth") private var clipboardFullWidth = false
    @State private var showsSearch = false
    @State private var showsSettings = false
    @State private var showsImport = false
    @State private var confirmsRestore = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 210, ideal: 224, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if model.needsRecovery {
                    HStack {
                        Label(L10n.tr("原数据无法读取，保存已暂停。可恢复备份或导入已导出的数据。"), systemImage: "exclamationmark.triangle")
                        Button(L10n.tr("恢复备份")) { confirmsRestore = true }
                        Button(L10n.tr("导入…")) { showsImport = true }
                    }.font(.caption).padding(10).background(.orange.opacity(0.15))
                }
                VStack(spacing: 0) {
                    if let group = model.selectedGroup {
                        GroupWorkspace(model: model, group: group, clotheslines: clipboardClotheslines).id(group.id)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        clipboardClotheslines
                        ContentUnavailableView(L10n.tr("还没有项目组"), systemImage: "square.grid.2x2")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
        .navigationTitle(model.selectedGroup?.name ?? "ProjectCanvas")
        .toolbar { ToolbarItem(placement: .primaryAction) { ClipboardDisplayMenu() } }
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

    @ViewBuilder
    private var clipboardClotheslines: some View {
                    if clipboardVisible {
                        ClipboardShelfView(history: model.clipboardHistory, allowsFullScreen: false, canvasClotheslineMode: true, showsSamples: true,
                            onAddToCanvas: { item in
                                if let groupID = model.selectedGroupID { withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { _ = model.addClipboardItem(item, to: groupID) } }
                            }, onClose: { clipboardVisible = false; notifyClipboardDisplayChange() })
                            .frame(maxWidth: clipboardFullWidth ? .infinity : 1100)
                            .frame(maxWidth: .infinity)
                    }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("项目组")).font(.title3.weight(.semibold))
                Spacer()
                Button(action: model.addGroup) { Image(systemName: "plus").font(.body.weight(.medium)) }
                    .buttonStyle(.borderless)
                    .help(L10n.tr("新建项目组"))
            }.padding(.horizontal, 14).padding(.top, 18)
            Button { showsSearch = true } label: {
                Label(L10n.tr("搜索项目"), systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("k", modifiers: .command)
            .padding(.horizontal, 12)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(model.groups) { group in
                        Button { model.selectedGroupID = group.id } label: {
                            HStack {
                                Image(systemName: "square.grid.2x2")
                                Text(group.name).lineLimit(1)
                                Spacer(minLength: 0)
                                if !group.cards.isEmpty {
                                    Text("\(group.cards.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 9)
                            .foregroundStyle(model.selectedGroupID == group.id ? Color.accentColor : Color.primary)
                            .background(model.selectedGroupID == group.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9))
                            .overlay(alignment: .leading) {
                                if model.selectedGroupID == group.id {
                                    Capsule().fill(Color.accentColor).frame(width: 3).padding(.vertical, 5)
                                }
                            }
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button(L10n.tr("重命名")) { model.beginRenaming(groupID: group.id) }
                            Button(L10n.tr("导出项目组…")) { exportGroup(group.id) }
                            Button(L10n.tr("删除项目组"), role: .destructive) { model.deleteGroup(group.id) }
                        }
                    }
                }.padding(.horizontal, 8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.tr("快速访问")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DisclosureGroup(L10n.tr("最近打开")) {
                        if model.recentProjects.isEmpty {
                            Text(L10n.tr("打开项目后显示在这里")).font(.caption).foregroundStyle(.secondary)
                        }
                        ProjectUsageList(model: model, results: model.recentProjects, showsCount: false)
                    }
                    DisclosureGroup(L10n.tr("常用项目")) {
                        if model.frequentProjects.isEmpty {
                            Text(L10n.tr("打开项目后显示在这里")).font(.caption).foregroundStyle(.secondary)
                        }
                        ProjectUsageList(model: model, results: model.frequentProjects, showsCount: true)
                    }
                }.padding(.horizontal, 14).padding(.top, 18)
            }
            VStack(alignment: .leading, spacing: 8) {
                Divider().padding(.bottom, 4)
                Menu {
                    Button(L10n.tr("导入项目组…")) { showsImport = true }
                    Button(L10n.tr("导出当前项目组…")) { if let id = model.selectedGroupID { exportGroup(id) } }
                    Button(L10n.tr("从最近备份恢复…")) { confirmsRestore = true }
                } label: { Label(L10n.tr("导入、导出与恢复"), systemImage: "externaldrive") }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { showsSettings = true } label: {
                    Label(L10n.tr("设置"), systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                }
                .keyboardShortcut(",", modifiers: .command)
                .help(L10n.tr("数据保存在这台 Mac 上 · ⌘⇧空格 显示桌面卡片"))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exportGroup(_ id: UUID) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "ProjectCanvas-group.json"
        if panel.runModal() == .OK, let url = panel.url { model.exportGroup(id, to: url) }
    }
}

private struct GroupWorkspace<Clotheslines: View>: View {
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let group: ProjectGroup
    let clotheslines: Clotheslines
    @State private var snapToGrid = true
    @State private var alignsToCards = true
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
    @State private var fitsWindow = false
    @State private var canvasSize = CGSize.zero
    @Namespace private var glassNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pinchStart: Double?
    @State private var selectedTag = ""
    @State private var showsBackgroundSettings = false
    @AppStorage(BackgroundTint.colorPreferenceKey) private var canvasTintColor = BackgroundTintColor.default.hex
    @AppStorage(BackgroundTint.opacityPreferenceKey) private var canvasTintOpacity = 0.0
    @AppStorage("clipboardShelfVisible") private var clipboardVisible = true
    @AppStorage(ClipboardAppearance.imageScaleKey) private var imageScale = 1.25
    @AppStorage(ClipboardAppearance.textSizeKey) private var textSize = 14.0
    private var clotheslineHeight: Double {
        clipboardVisible ? ClipboardAppearance(imageScale: imageScale, textSize: textSize).canvasClotheslineHeight : 0
    }
    private var visibleGroup: ProjectGroup { model.filteredGroup(group, tag: selectedTag) }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ZStack {
                    // The canvas runs under the glass toolbar (macOS 26). A neutral band the height of the
                    // toolbar keeps the title area untinted, like a hard scroll-edge effect.
                    CanvasBackgroundView(theme: group.canvasTheme)
                        .overlay(alignment: .top) {
                            Color(nsColor: .windowBackgroundColor)
                                .frame(height: geometry.safeAreaInsets.top)
                                .allowsHitTesting(false)
                        }
                        .ignoresSafeArea(edges: .top)
                    let size = CanvasGeometry.extent(cards: visibleGroup.cards, minimumHeight: 0)
                    CanvasScrollView(size: CGSize(width: max(geometry.size.width, size.width * zoom), height: max(geometry.size.height, (size.height + clotheslineHeight) * zoom)), offset: $offset, onViewportCommit: { [zoom] position in
                        fitsWindow = false
                        model.updateViewport(CanvasViewport(zoom: zoom, offsetX: position.x, offsetY: position.y), in: group.id)
                    }) {
                        VStack(spacing: 0) {
                            clotheslines
                                .frame(width: size.width, height: clotheslineHeight)
                                .scaleEffect(zoom, anchor: .topLeading)
                                .frame(width: size.width * zoom, height: clotheslineHeight * zoom, alignment: .topLeading)
                            CanvasBoard(model: model, group: visibleGroup, zoom: zoom, isEditing: true, snapToGrid: snapToGrid,
                                        selectedCardIDs: $selectedCardIDs, selectedConnectionID: $selectedConnectionID,
                                        isConnecting: $isConnecting, firstConnectionCardID: $firstConnectionCardID,
                                        highlightDirection: highlightDirection, onOpenSettings: { projectToConfigure = $0 }, onRelocate: relocate,
                                        onOpenDetails: { projectDetails = $0 }, onBackgroundSettings: { showsBackgroundSettings = true },
                                        onAddFolders: chooseFolders, onShowAll: { fit(in: geometry.size) },
                                        minimumSize: CGSize(width: size.width, height: max(0, geometry.size.height / zoom - clotheslineHeight)), minimumHeight: 0,
                                        alignsToCards: alignsToCards)
                                .background {
                                    Color.clear.contentShape(Rectangle()).contextMenu {
                                        CanvasBackgroundMenu(onCustomize: { showsBackgroundSettings = true }, groupTheme: groupThemeBinding)
                                        Button(L10n.tr("添加文件夹（⇧⌘O）"), action: chooseFolders)
                                        Button(L10n.tr("适应视图")) { fit(in: geometry.size) }
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    .simultaneousGesture(MagnificationGesture().onChanged { scale in
                        if pinchStart == nil { pinchStart = zoom; fitsWindow = false }
                        zoom = min(2, max(0.1, (pinchStart ?? zoom) * scale))
                    }.onEnded { _ in pinchStart = nil; saveViewport() })
                    .onDrop(of: [UTType.fileURL], isTargeted: nil, perform: dropFolders)
                    if group.cards.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.tr("添加项目文件夹"), systemImage: "folder.badge.plus")
                        } description: { Text(L10n.tr("从 Finder 拖入项目文件夹，或将上方剪贴板内容拖到这里。")) }
                        actions: { Button(L10n.tr("选择文件夹"), action: chooseFolders) }
                    } else if visibleGroup.cards.isEmpty {
                        ContentUnavailableView {
                            Label(L10n.tr("没有匹配的项目"), systemImage: "line.3.horizontal.decrease.circle")
                        } actions: { Button(L10n.tr("清除筛选")) { selectedTag = "" } }
                    }
                    // Glass elements float directly over the canvas. Shapes in one container blend when
                    // closer than its spacing, so it stays below the gaps to keep each element separate.
                    let extent = CanvasGeometry.extent(cards: visibleGroup.cards, minimumHeight: 0)
                    let showsMinimap = !visibleGroup.cards.isEmpty &&
                        CanvasMinimap.isUseful(extent: extent, clotheslineHeight: clotheslineHeight, zoom: zoom, viewport: geometry.size)
                    GlassEffectContainer(spacing: 2) {
                    VStack(alignment: .trailing, spacing: 10) {
                        Spacer()
                        if showsMinimap {
                            CanvasMinimap(cards: visibleGroup.cards, clotheslineHeight: clotheslineHeight, extent: extent,
                                          zoom: zoom, viewport: geometry.size, offset: Binding(get: { offset }, set: { fitsWindow = false; offset = $0 }))
                                .glassEffectID("minimap", in: glassNamespace)
                                .padding(.trailing, 14)
                        }
                        HStack(spacing: 8) {
                            if isConnecting { Text(firstConnectionCardID == nil ? L10n.tr("先点起点，再点终点") : L10n.tr("点击终点完成连线")).font(.caption) }
                            if !selectedTag.isEmpty {
                                Label(L10n.format("%@ · 显示 %d / %d 个项目", selectedTag, visibleGroup.cards.count, group.cards.count),
                                      systemImage: "line.3.horizontal.decrease.circle.fill")
                                    .font(.caption).lineLimit(1)
                                Button(L10n.tr("清除筛选")) { selectedTag = "" }
                                    .buttonStyle(.glassProminent)
                            }
                            if !selectedCardIDs.isEmpty {
                                Text(L10n.format("已选 %d 张", selectedCardIDs.count)).font(.caption)
                            }
                            Button(L10n.tr("适应视图")) { fit(in: geometry.size) }
                            Button(L10n.tr("回到卡片")) {
                                fitsWindow = false
                                offset = .zero
                            }
                        }
                        .foregroundStyle(.secondary)
                        .modifier(CanvasFloatingControls())
                        .padding([.horizontal, .bottom], 14)
                    }
                    }
                    .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: showsMinimap)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .dropDestination(for: ClipboardCanvasTransfer.self) { items, location in
                    guard let item = items.first else { return false }
                    let position = CanvasGeometry.positionForDrop(
                        at: CGPoint(x: location.x - max(0, (geometry.size.width - CanvasGeometry.extent(cards: visibleGroup.cards).width * zoom) / 2),
                                    y: location.y - clotheslineHeight * zoom), zoom: zoom, scrollOffset: offset)
                    let added = withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        model.addClipboardItem(item, to: group.id, at: position)
                    }
                    if added { selectedTag = "" }
                    return added
                }
                .onAppear { canvasSize = geometry.size }
                .onChange(of: geometry.size) { _, size in
                    canvasSize = size
                    if fitsWindow { fit(in: size) }
                }
                .onChange(of: clotheslineHeight) { _, _ in
                    if fitsWindow { fit(in: geometry.size) }
                }
            }
        }
        .toolbar { workspaceToolbar }
        .onChange(of: canvasTintColor) { _, _ in refreshDesktopBackground() }
        .onChange(of: canvasTintOpacity) { _, _ in refreshDesktopBackground() }
        .onAppear {
            let viewport = group.viewport ?? CanvasViewport()
            zoom = min(2, max(0.1, viewport.zoom))
            offset = CGPoint(x: viewport.offsetX, y: viewport.offsetY)
            loadedViewport = true
            locateRequestedCard()
        }
        .onChange(of: model.locateRequest) { _, _ in locateRequestedCard() }
        .onChange(of: selectedTag) { _, _ in
            selectedCardIDs.formIntersection(Set(visibleGroup.cards.map(\.id)))
            selectedConnectionID = nil
            isConnecting = false; firstConnectionCardID = nil
        }
        .onChange(of: model.tags(in: group)) { _, tags in
            if !selectedTag.isEmpty && !tags.contains(selectedTag) { selectedTag = "" }
        }
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

    @ToolbarContentBuilder
    private var workspaceToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: chooseFolders) {
                Label(L10n.tr("添加文件夹（⇧⌘O）"), systemImage: "folder.badge.plus")
            }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button { model.toggleDesktopDisplay() } label: {
                Label(L10n.tr("显示或隐藏桌面卡片（⌘⇧空格）"), systemImage: model.isDesktopDisplayOn ? "rectangle.slash" : "menubar.dock.rectangle")
            }
            backgroundButton
            Button { Task { await model.refreshGitStatuses() } } label: {
                Label(L10n.tr("刷新 Git 状态"), systemImage: "arrow.clockwise")
            }.disabled(model.isRefreshingGit)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItemGroup(placement: .primaryAction) {
            tagFilterMenu
            editingMenu
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) { zoomControl }
    }

    private var tagFilterMenu: some View {
        Menu {
            Picker(L10n.tr("标签筛选"), selection: $selectedTag) {
                Text(L10n.tr("全部标签")).tag("")
                ForEach(model.tags(in: group), id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.inline)
        } label: {
            Label(L10n.tr("标签筛选"), systemImage: selectedTag.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
        }
        .help(selectedTag.isEmpty ? L10n.tr("标签筛选") : L10n.format("标签：%@", selectedTag))
    }

    /// Undo/redo live in the Edit menu; zoom is one compact control instead of three items.
    private var zoomControl: some View {
        ControlGroup {
            Button { fitsWindow = false; zoom = max(0.1, zoom - 0.1) } label: {
                Label(L10n.tr("缩小"), systemImage: "minus.magnifyingglass")
            }.keyboardShortcut("-", modifiers: .command)
            Menu {
                Button(L10n.tr("适应视图")) { fit(in: canvasSize) }
                Divider()
                ForEach([0.5, 0.75, 1, 1.5, 2], id: \.self) { level in
                    Button("\(Int(level * 100))%") { fitsWindow = false; zoom = level }
                }
            } label: {
                Text("\(Int(zoom * 100))%").font(.caption.monospacedDigit())
            }
            .accessibilityLabel(L10n.tr("缩放比例"))
            .help(L10n.tr("缩放比例"))
            Button { fitsWindow = false; zoom = min(2, zoom + 0.1) } label: {
                Label(L10n.tr("放大"), systemImage: "plus.magnifyingglass")
            }.keyboardShortcut("=", modifiers: .command)
        }
    }

    private var groupThemeBinding: Binding<GroupCanvasTheme?> {
        Binding(get: { group.canvasTheme }, set: { model.setCanvasTheme($0, for: group.id) })
    }

    /// Edits the group's own theme when it has one, otherwise the shared background.
    private var themeColorBinding: Binding<String> {
        Binding(get: { group.canvasTheme?.colorHex ?? canvasTintColor }, set: { hex in
            if var theme = group.canvasTheme { theme.colorHex = hex; model.setCanvasTheme(theme, for: group.id) } else { canvasTintColor = hex }
        })
    }

    private var themeOpacityBinding: Binding<Double> {
        Binding(get: { group.canvasTheme?.opacity ?? canvasTintOpacity }, set: { value in
            if var theme = group.canvasTheme { theme.opacity = value; model.setCanvasTheme(theme, for: group.id) } else { canvasTintOpacity = value }
        })
    }

    private var backgroundButton: some View {
        Button { showsBackgroundSettings.toggle() } label: {
            Label(L10n.tr("画布背景"), systemImage: "paintpalette")
        }
        .popover(isPresented: $showsBackgroundSettings) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L10n.tr("画布背景")).font(.headline)
                Toggle(L10n.format("仅用于“%@”", group.name), isOn: Binding(
                    get: { group.canvasTheme != nil },
                    set: { model.setCanvasTheme($0 ? GroupCanvasTheme(colorHex: canvasTintColor, opacity: canvasTintOpacity) : nil, for: group.id) }))
                BackgroundTintControls(colorHex: themeColorBinding, opacity: themeOpacityBinding)
                Text(L10n.tr(group.canvasTheme == nil ? "颜色和浓度同时应用于内容区与桌面磨砂背景。" : "只改变这个组的画布，其他组和桌面背景不受影响。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(L10n.tr("恢复默认外观")) {
                        if group.canvasTheme != nil { model.setCanvasTheme(nil, for: group.id) }
                        else { canvasTintColor = BackgroundTintColor.default.hex; canvasTintOpacity = 0 }
                    }
                    Spacer()
                    Button(L10n.tr("完成")) { showsBackgroundSettings = false }
                }
            }.padding(18).frame(width: 360)
        }
    }

    private func refreshDesktopBackground() {
        NotificationCenter.default.post(name: Notification.Name("ProjectCanvasDesktopPreferencesChanged"), object: nil)
    }

    private var editingMenu: some View {
        Menu {
            Menu(L10n.tr("布局")) {
                Button(L10n.tr("网格布局预览…")) { model.autoLayoutCards(in: group.id) }
                Button(L10n.tr("关系布局预览…")) { model.layoutPreview = model.makeLayoutPreview(in: group.id, mode: .relationships) }
                Button(L10n.tr("对齐到网格")) { model.alignCardsToGrid(in: group.id) }
                Toggle(L10n.tr("拖动吸附"), isOn: $snapToGrid)
                Toggle(L10n.tr("对齐卡片"), isOn: $alignsToCards)
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
            Divider()
            Button(L10n.tr("删除选中项"), role: .destructive, action: deleteSelection)
                .disabled(selectedCardIDs.isEmpty && selectedConnectionID == nil)
        } label: {
            Label(L10n.tr("编辑"), systemImage: "slider.horizontal.3")
        }
        .help(L10n.tr("编辑"))
    }

    private func locateRequestedCard() {
        guard let request = model.locateRequest, request.groupID == group.id,
              let card = group.cards.first(where: { $0.id == request.cardID }) else { return }
        selectedTag = ""
        selectedCardIDs = [card.id]
        fitsWindow = false
        zoom = 1
        offset = CGPoint(x: max(0, card.x - 60), y: clotheslineHeight + max(0, card.y - 60))
        model.locateRequest = nil
    }

    private func saveViewport() {
        guard loadedViewport, pinchStart == nil else { return }
        model.updateViewport(CanvasViewport(zoom: zoom, offsetX: offset.x, offsetY: offset.y), in: group.id)
    }

    private func fit(in size: CGSize) {
        guard size.width > 0, size.height > 50 else { return }
        let width = CanvasGeometry.extent(cards: visibleGroup.cards).width
        let height = clotheslineHeight + max(130, (visibleGroup.cards.map(\.y).max() ?? 0) + 130)
        fitsWindow = true
        zoom = min(1.5, max(0.1, min(size.width / width, (size.height - 50) / height)))
        offset = .zero
    }

    private func deleteSelection() {
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
