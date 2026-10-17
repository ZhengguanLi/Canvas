import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let clipboardHistory = ClipboardHistory()
    @Published private(set) var projects: [Project]
    @Published private(set) var groups: [ProjectGroup]
    @Published var selectedGroupID: UUID? { didSet { if !restoring { persist(rotatingBackup: false) } } }
    @Published var defaultEditor: EditorChoice = .vscode { didSet { if !restoring { persist() } } }
    @Published var defaultOpenInNewWindow = false { didSet { if !restoring { persist() } } }
    @Published private(set) var gitStatuses: [UUID: GitStatus] = [:]
    @Published private(set) var projectKinds: [UUID: ProjectKind] = [:]
    @Published private(set) var needsRecovery = false
    @Published private(set) var isRefreshingGit = false
    @Published var alertMessage: String?
    @Published var isEditingName = false
    @Published var layoutPreview: LayoutPreview?
    @Published var locateRequest: CanvasLocateRequest?
    @Published var nameDraft = ""
    @Published private(set) var isDesktopDisplayOn: Bool
    @Published private(set) var desktopDisplayMode: DesktopDisplayMode
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    private var editingGroupID: UUID?
    private var editingCardID: UUID?
    private let preferences: UserDefaults
    private let storage: CanvasStorage
    private let persistence: CanvasPersistence
    private var terminationObserver: NSObjectProtocol?
    private var restoring = false
    private(set) var desktopDisplayController: DesktopDisplayController?
    private var undoStack: [ProjectCanvasData] = []
    private var redoStack: [ProjectCanvasData] = []

    init(storageURL: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        self.isDesktopDisplayOn = preferences.bool(forKey: "desktopDisplayEnabled")
        self.desktopDisplayMode = DesktopDisplayMode(rawValue: preferences.string(forKey: "desktopDisplayMode") ?? "") ?? .foregroundOverlay
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ProjectCanvas", isDirectory: true)
        storage = CanvasStorage(url: storageURL ?? appSupport.appendingPathComponent("canvas.json"))
        persistence = CanvasPersistence(storage: storage)
        let saved: ProjectCanvasData
        var loadError: Error?
        do { saved = try storage.load() ?? .empty }
        catch { saved = .empty; loadError = error }
        projects = saved.projects
        groups = saved.groups.isEmpty ? [ProjectGroup(name: L10n.tr("我的项目"))] : saved.groups
        selectedGroupID = groups.contains(where: { $0.id == saved.selectedGroupID }) ? saved.selectedGroupID : groups.first?.id
        defaultEditor = saved.defaultEditor ?? .vscode
        defaultOpenInNewWindow = saved.defaultOpenInNewWindow ?? false
        needsRecovery = storage.requiresRecovery
        persistence.onFailure = { [weak self] error, recovery, id in
            Task { @MainActor [weak self] in
                guard let self, self.persistence.isCurrentFailure(id) else { return }
                self.needsRecovery = recovery
                self.alertMessage = L10n.format("保存失败：%@", error.localizedDescription)
            }
        }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: nil
        ) { [persistence] _ in persistence.flush() }
        if let loadError { alertMessage = L10n.format("加载失败，原文件已保留，已暂停保存：%@", loadError.localizedDescription) }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        persistence.flush()
    }

    var selectedGroup: ProjectGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    func toggleDesktopDisplay() {
        if isDesktopDisplayOn {
            desktopDisplayController?.hide()
            isDesktopDisplayOn = false
        } else {
            if desktopDisplayController == nil {
                desktopDisplayController = DesktopDisplayController(model: self)
            }
            isDesktopDisplayOn = true
            desktopDisplayController?.show()
        }
        preferences.set(isDesktopDisplayOn, forKey: "desktopDisplayEnabled")
    }

    func setDesktopDisplayMode(_ mode: DesktopDisplayMode) {
        desktopDisplayMode = mode
        preferences.set(mode.rawValue, forKey: "desktopDisplayMode")
    }

    func restoreDesktopDisplayIfNeeded() {
        if desktopDisplayController == nil {
            desktopDisplayController = DesktopDisplayController(model: self)
        }
        if isDesktopDisplayOn { desktopDisplayController?.show() }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        restore(previous, preservingUsage: true)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        restore(next, preservingUsage: true)
    }

    func addGroup() {
        recordUndo()
        let group = ProjectGroup(name: L10n.tr("新建组"))
        groups.append(group)
        restoring = true
        selectedGroupID = group.id
        restoring = false
        persist()
        beginRenaming(groupID: group.id)
    }

    func beginRenaming(groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        editingGroupID = groupID
        editingCardID = nil
        nameDraft = group.name
        isEditingName = true
    }

    func beginRenaming(cardID: UUID) {
        guard let group = selectedGroup,
              let card = group.cards.first(where: { $0.id == cardID }) else { return }
        editingGroupID = group.id
        editingCardID = cardID
        nameDraft = card.customName ?? project(for: card)?.folderName ?? L10n.tr("项目")
        isEditingName = true
    }

    func saveName() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let groupID = editingGroupID,
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else {
            isEditingName = false
            return
        }

        if let cardID = editingCardID,
           let cardIndex = groups[groupIndex].cards.firstIndex(where: { $0.id == cardID }) {
            let projectName = project(for: groups[groupIndex].cards[cardIndex])?.folderName
            let newName = trimmed == projectName ? nil : trimmed
            guard groups[groupIndex].cards[cardIndex].customName != newName else {
                isEditingName = false
                return
            }
            recordUndo()
            groups[groupIndex].cards[cardIndex].customName = newName
        } else {
            guard groups[groupIndex].name != trimmed else {
                isEditingName = false
                return
            }
            recordUndo()
            groups[groupIndex].name = trimmed
        }
        isEditingName = false
        persist()
    }

    func deleteGroup(_ groupID: UUID) {
        guard groups.contains(where: { $0.id == groupID }) else { return }
        recordUndo()
        groups.removeAll { $0.id == groupID }
        if groups.isEmpty { groups = [ProjectGroup(name: L10n.tr("我的项目"))] }
        restoring = true
        if selectedGroupID == groupID { selectedGroupID = groups.first?.id }
        restoring = false
        persist()
    }

    func addProject(folderURL: URL) {
        guard let groupID = selectedGroupID else { return }
        addProjects(folderURLs: [folderURL], to: groupID)
    }

    func addProjects(folderURLs: [URL], to groupID: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let urls = folderURLs.filter { url in
            var directory: ObjCBool = false
            return url.isFileURL && FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
        }
        guard !urls.isEmpty else { alertMessage = L10n.tr("请选择或拖入文件夹。"); return }
        guard urls.contains(where: { url in
            guard let project = projects.first(where: { $0.folderPath == url.standardizedFileURL.path }) else { return true }
            return !groups[groupIndex].cards.contains(where: { $0.projectID == project.id })
        }) else { return }
        recordUndo()
        for url in urls {
            let normalized = url.standardizedFileURL.path
            let project = projects.first(where: { $0.folderPath == normalized }) ?? Project(folderURL: url)
            guard !groups[groupIndex].cards.contains(where: { $0.projectID == project.id }) else { continue }
            if !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
            let next = groups[groupIndex].cards.count
            groups[groupIndex].cards.append(ProjectCard(projectID: project.id, x: 96 + Double(next % 4) * 260, y: 96 + Double(next / 4) * 160))
        }
        persist()
    }

    func copyClipboardContent(_ content: CanvasClipboardContent) {
        if !content.copy() { alertMessage = L10n.tr("复制失败，请重试") }
    }

    @discardableResult func addClipboardItem(_ item: ClipboardCanvasTransfer, to groupID: UUID, at position: CGPoint? = nil) -> Bool {
        let content: CanvasClipboardContent
        switch item.kind {
        case .text:
            guard let entry = clipboardHistory.texts.first(where: { $0.id == item.id }) else { return false }
            content = .text(entry.text)
        case .image:
            guard let entry = clipboardHistory.images.first(where: { $0.id == item.id }),
                  let tiff = entry.thumbnail.tiffRepresentation,
                  let preview = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
            content = .image(data: entry.data, type: entry.type.rawValue, preview: preview)
        }
        return addClipboardContent(content, to: groupID, at: position)
    }

    /// Adds an empty note below existing cards and returns its id for immediate editing.
    @discardableResult func addNote(to groupID: UUID, at position: CGPoint? = nil) -> UUID? {
        guard addClipboardContent(.note(""), to: groupID, at: position) else { return nil }
        return groups.first(where: { $0.id == groupID })?.cards.last?.id
    }

    func updateNote(_ cardID: UUID, text: String, in groupID: UUID) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }),
              let c = groups[g].cards.firstIndex(where: { $0.id == cardID }),
              case .note(let current) = groups[g].cards[c].clipboard, current != text,
              CanvasClipboardContent.note(text).isValid else { return }
        recordUndo()
        groups[g].cards[c].clipboard = .note(text)
        persist()
    }

    @discardableResult func addClipboardContent(_ content: CanvasClipboardContent, to groupID: UUID, at position: CGPoint? = nil) -> Bool {
        guard content.isValid, let index = groups.firstIndex(where: { $0.id == groupID }) else { return false }
        guard groups[index].cards.compactMap(\.clipboard).reduce(content.byteCount, { $0 + $1.byteCount }) <= 64 * 1024 * 1024 else {
            alertMessage = L10n.tr("画布内容已达到 64 MB，请先删除部分图片或文字。")
            return false
        }
        let point = position ?? CGPoint(x: 96, y: (groups[index].cards.map(\.y).max() ?? -36) + 132)
        guard point.x.isFinite && point.y.isFinite else { return false }
        let card = ProjectCard(clipboard: content, x: max(20, point.x), y: max(20, point.y))
        recordUndo()
        groups[index].cards.append(card)
        persist()
        if position == nil {
            selectedGroupID = groupID
            locateRequest = CanvasLocateRequest(groupID: groupID, cardID: card.id)
        }
        return true
    }

    func removeCards(_ ids: Set<UUID>, from groupID: UUID) {
        guard !ids.isEmpty, let index = groups.firstIndex(where: { $0.id == groupID }), groups[index].cards.contains(where: { ids.contains($0.id) }) else { return }
        recordUndo()
        removeRegionMembers(ids, at: index)
        groups[index].cards.removeAll { ids.contains($0.id) }
        groups[index].connections.removeAll { ids.contains($0.fromCardID) || ids.contains($0.toCardID) }
        persist()
    }

    func moveCard(_ cardID: UUID, to position: CGPoint, in groupID: UUID) {
        guard let card = groups.first(where: { $0.id == groupID })?.cards.first(where: { $0.id == cardID }) else { return }
        moveCards(ids: [cardID], by: CGSize(width: position.x - card.x, height: position.y - card.y), in: groupID)
    }

    /// Expands the canvas when a centered desktop card crosses its coordinate origin.
    func moveDesktopCard(_ cardID: UUID, to position: CGPoint, in groupID: UUID) {
        guard position.x.isFinite, position.y.isFinite,
              let groupIndex = groups.firstIndex(where: { $0.id == groupID }),
              let cardIndex = groups[groupIndex].cards.firstIndex(where: { $0.id == cardID }) else { return }
        var group = groups[groupIndex]
        guard group.cards[cardIndex].x != position.x || group.cards[cardIndex].y != position.y else { return }
        let shift = CGPoint(x: max(0, 20 - position.x), y: max(0, 20 - position.y))
        group.cards[cardIndex].x = position.x
        group.cards[cardIndex].y = position.y
        if shift != .zero {
            for index in group.cards.indices {
                group.cards[index].x += shift.x
                group.cards[index].y += shift.y
            }
            let previousOffset = group.coordinateOffset ?? .zero
            group.coordinateOffset = CGPoint(x: previousOffset.x + shift.x, y: previousOffset.y + shift.y)
            if var viewport = group.viewport {
                viewport.offsetX += shift.x * viewport.zoom
                viewport.offsetY += shift.y * viewport.zoom
                group.viewport = viewport
            }
        }
        recordUndo()
        groups[groupIndex] = group
        persist()
    }

    func moveCards(ids: Set<UUID>, by offset: CGSize, in groupID: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let indices = groups[groupIndex].cards.indices.filter { ids.contains(groups[groupIndex].cards[$0].id) }
        guard !indices.isEmpty else { return }
        let offset = CanvasGeometry.clampedOffset(offset, cards: indices.map { groups[groupIndex].cards[$0] })
        let moves = indices.map { index in
            let card = groups[groupIndex].cards[index]
            return (index, max(20, card.x + offset.width), max(20, card.y + offset.height))
        }
        guard moves.contains(where: { index, x, y in
            groups[groupIndex].cards[index].x != x || groups[groupIndex].cards[index].y != y
        }) else { return }
        recordUndo()
        for (index, x, y) in moves {
            groups[groupIndex].cards[index].x = x
            groups[groupIndex].cards[index].y = y
        }
        persist()
    }

    func autoLayoutCards(in groupID: UUID) {
        layoutPreview = makeLayoutPreview(in: groupID, mode: .grid)
    }

    func makeLayoutPreview(in groupID: UUID, mode: LayoutMode) -> LayoutPreview? {
        groups.first(where: { $0.id == groupID }).map { ProjectLayout.preview($0, mode: mode) }
    }

    @discardableResult func applyLayout(_ preview: LayoutPreview) -> Bool {
        guard let index = groups.firstIndex(where: { $0.id == preview.original.id }), groups[index] == preview.original else {
            alertMessage = L10n.tr("画布已更改，请重新生成布局预览。")
            return false
        }
        guard groups[index].cards != preview.proposed.cards else { return true }
        recordUndo()
        groups[index].cards = preview.proposed.cards
        persist()
        return true
    }

    func searchProjects(_ query: String) -> [ProjectSearchResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return groups.flatMap { group in
            group.cards.compactMap { card in
                guard let project = project(for: card), query.isEmpty ||
                        (card.customName ?? "").localizedCaseInsensitiveContains(query) ||
                        project.folderName.localizedCaseInsensitiveContains(query) ||
                        project.folderPath.localizedCaseInsensitiveContains(query) ||
                        project.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) else { return nil }
                return ProjectSearchResult(groupID: group.id, groupName: group.name, card: card, project: project)
            }
        }
    }

    func locate(_ result: ProjectSearchResult) {
        selectedGroupID = result.groupID
        locateRequest = CanvasLocateRequest(groupID: result.groupID, cardID: result.card.id)
    }

    @discardableResult func saveProjectDetails(_ id: UUID, notes: String, links: [ProjectLink], tags: [String]? = nil, configurations: [LaunchConfiguration]? = nil) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return false }
        guard links.allSatisfy({ $0.validatedURL != nil }), Set(links.map(\.id)).count == links.count else {
            alertMessage = L10n.tr("链接需要名称和有效的 HTTP 或 HTTPS 地址。"); return false
        }
        let configurations = configurations ?? projects[index].launchConfigurations
        guard configurations.allSatisfy(\.isValid), Set(configurations.map(\.id)).count == configurations.count else {
            alertMessage = L10n.tr("启动配置需要名称、命令和有效的环境变量名称。"); return false
        }
        var seen = Set<String>()
        let tags = (tags ?? projects[index].tags).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        guard projects[index].notes != notes || projects[index].links != links ||
                projects[index].tags != tags || projects[index].launchConfigurations != configurations else { return true }
        recordUndo()
        projects[index].notes = notes
        projects[index].links = links
        projects[index].tags = tags
        projects[index].launchConfigurations = configurations
        persist()
        return true
    }

    @discardableResult func saveProjectWorkflow(_ id: UUID, tags: [String], configurations: [LaunchConfiguration]) -> Bool {
        guard let project = projects.first(where: { $0.id == id }) else { return false }
        return saveProjectDetails(id, notes: project.notes ?? "", links: project.links ?? [], tags: tags, configurations: configurations)
    }

    func tags(in group: ProjectGroup) -> [String] {
        var seen = Set<String>()
        return group.cards.compactMap { project(for: $0) }.flatMap(\.tags)
            .filter { seen.insert($0.lowercased()).inserted }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func filteredGroup(_ group: ProjectGroup, tag: String) -> ProjectGroup {
        guard !tag.isEmpty else { return group }
        var filtered = group
        filtered.cards = group.cards.filter { card in
            project(for: card)?.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } ?? false
        }
        let ids = Set(filtered.cards.map(\.id))
        filtered.connections = group.connections.filter { ids.contains($0.fromCardID) && ids.contains($0.toCardID) }
        filtered.regions = group.regions.compactMap { original in
            var region = original; region.cardIDs.formIntersection(ids)
            return region.cardIDs.isEmpty ? nil : region
        }
        return filtered
    }

    private var usedProjects: [ProjectSearchResult] {
        var seen = Set<UUID>()
        let results = searchProjects("")
        let preferred = results.filter { $0.groupID == selectedGroupID } + results.filter { $0.groupID != selectedGroupID }
        return preferred.filter { $0.project.lastOpenedAt != nil && seen.insert($0.project.id).inserted }
    }

    var recentProjects: [ProjectSearchResult] {
        usedProjects.sorted {
            let a = $0.project.lastOpenedAt ?? .distantPast, b = $1.project.lastOpenedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
    }

    var frequentProjects: [ProjectSearchResult] {
        recentProjects.sorted {
            if $0.project.openCount != $1.project.openCount { return $0.project.openCount > $1.project.openCount }
            let a = $0.project.lastOpenedAt ?? .distantPast, b = $1.project.lastOpenedAt ?? .distantPast
            return a == b ? $0.id < $1.id : a > b
        }
    }

    func recordProjectOpened(_ id: UUID, at date: Date = Date()) {
        guard date.timeIntervalSince1970.isFinite, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].lastOpenedAt = date
        if projects[index].openCount < Int.max { projects[index].openCount += 1 }
        persist(rotatingBackup: false)
    }

    func runProject(_ project: Project, configuration: LaunchConfiguration) {
        Task {
            do {
                try await ProjectLauncher.run(project, configuration: configuration)
                recordProjectOpened(project.id)
                if desktopDisplayMode == .foregroundOverlay && isDesktopDisplayOn { toggleDesktopDisplay() }
            } catch { alertMessage = error.localizedDescription }
        }
    }

    func addRegion(name: String, color: CardColor, cardIDs: Set<UUID>, in groupID: UUID) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !cardIDs.isEmpty, let index = groups.firstIndex(where: { $0.id == groupID }),
              Set(groups[index].cards.map(\.id)).isSuperset(of: cardIDs) else { return }
        recordUndo()
        groups[index].regions.append(ProjectRegion(name: name, color: color, cardIDs: cardIDs))
        persist()
    }

    func updateRegion(_ id: UUID, name: String, color: CardColor, in groupID: UUID) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let g = groups.firstIndex(where: { $0.id == groupID }),
              let r = groups[g].regions.firstIndex(where: { $0.id == id }),
              groups[g].regions[r].name != name || groups[g].regions[r].color != color else { return }
        recordUndo()
        groups[g].regions[r].name = name
        groups[g].regions[r].color = color
        persist()
    }

    func removeRegion(_ id: UUID, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }), groups[index].regions.contains(where: { $0.id == id }) else { return }
        recordUndo()
        groups[index].regions.removeAll { $0.id == id }
        persist()
    }

    func moveRegion(_ id: UUID, by offset: CGSize, in groupID: UUID) {
        guard let region = groups.first(where: { $0.id == groupID })?.regions.first(where: { $0.id == id }) else { return }
        moveCards(ids: region.cardIDs, by: offset, in: groupID)
    }

    private func removeRegionMembers(_ ids: Set<UUID>, at index: Int) {
        for r in groups[index].regions.indices { groups[index].regions[r].cardIDs.subtract(ids) }
        groups[index].regions.removeAll { $0.cardIDs.isEmpty }
    }

    func alignCardsToGrid(in groupID: UUID, spacing: Double = 32) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        let positions = groups[groupIndex].cards.map { card in
            (max(20, (card.x / spacing).rounded() * spacing), max(20, (card.y / spacing).rounded() * spacing))
        }
        guard groups[groupIndex].cards.indices.contains(where: { cardIndex in
            let card = groups[groupIndex].cards[cardIndex]
            return card.x != positions[cardIndex].0 || card.y != positions[cardIndex].1
        }) else { return }
        recordUndo()
        for cardIndex in groups[groupIndex].cards.indices {
            groups[groupIndex].cards[cardIndex].x = positions[cardIndex].0
            groups[groupIndex].cards[cardIndex].y = positions[cardIndex].1
        }
        persist()
    }

    /// Not an undo step: slider drags would otherwise flood the undo history.
    func setCanvasTheme(_ theme: GroupCanvasTheme?, for groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }), groups[index].canvasTheme != theme else { return }
        groups[index].canvasTheme = theme
        persist(rotatingBackup: false)
    }

    /// Duplicates note and clipboard cards; a project appears at most once per group, so project cards are skipped.
    @discardableResult func duplicateCards(_ ids: Set<UUID>, in groupID: UUID) -> Set<UUID> {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return [] }
        let sources = groups[index].cards.filter { ids.contains($0.id) && $0.clipboard != nil }
        guard !sources.isEmpty else { return [] }
        recordUndo()
        let copies = sources.compactMap { source -> ProjectCard? in
            guard let content = source.clipboard else { return nil }
            var copy = ProjectCard(clipboard: content, x: source.x + 24, y: source.y + 24)
            copy.color = source.color
            return copy
        }
        groups[index].cards.append(contentsOf: copies)
        persist()
        return Set(copies.map(\.id))
    }

    func removeCard(_ cardID: UUID, from groupID: UUID) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupID }) else { return }
        guard groups[groupIndex].cards.contains(where: { $0.id == cardID }) else { return }
        recordUndo()
        removeRegionMembers([cardID], at: groupIndex)
        groups[groupIndex].cards.removeAll { $0.id == cardID }
        groups[groupIndex].connections.removeAll { $0.fromCardID == cardID || $0.toCardID == cardID }
        persist()
    }

    func toggleConnections(for groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else { return }
        recordUndo()
        groups[index].showsConnections.toggle()
        persist()
    }

    func connectCards(_ firstID: UUID, _ secondID: UUID, in groupID: UUID) {
        guard firstID != secondID,
              let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].cards.contains(where: { $0.id == firstID }),
              groups[index].cards.contains(where: { $0.id == secondID }),
              !groups[index].connections.contains(where: {
                  ($0.fromCardID == firstID && $0.toCardID == secondID)
              }) else { return }
        recordUndo()
        groups[index].connections.append(ProjectConnection(fromCardID: firstID, toCardID: secondID))
        groups[index].showsConnections = true
        persist()
    }

    func removeConnection(_ connectionID: UUID, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].connections.contains(where: { $0.id == connectionID }) else { return }
        recordUndo()
        groups[index].connections.removeAll { $0.id == connectionID }
        if groups[index].connections.isEmpty { groups[index].showsConnections = false }
        persist()
    }

    func project(for card: ProjectCard) -> Project? {
        projects.first { $0.id == card.projectID }
    }

    /// `editorOverride` opens with a specific app once without changing the project's setting.
    func openProject(_ project: Project, editorOverride: EditorChoice? = nil) {
        let editor = editorOverride ?? project.editor ?? defaultEditor
        let newWindow = project.openInNewWindow ?? defaultOpenInNewWindow
        Task {
            do {
                try await ProjectLauncher.open(project, editor: editor, newWindow: newWindow)
                recordProjectOpened(project.id)
                if desktopDisplayMode == .foregroundOverlay && isDesktopDisplayOn { toggleDesktopDisplay() }
            } catch { alertMessage = error.localizedDescription }
        }
    }

    private func persist(rotatingBackup: Bool = true) {
        guard !restoring else { return }
        guard !needsRecovery else {
            alertMessage = CanvasStorage.StorageError.recoveryRequired.localizedDescription
            return
        }
        persistence.save(currentSnapshot, rotatingBackup: rotatingBackup)
    }

    /// Used at normal application termination and as a deterministic persistence barrier.
    func flushPersistence() { persistence.flush() }

    private var currentSnapshot: ProjectCanvasData {
        var data = ProjectCanvasData(projects: projects, groups: groups, selectedGroupID: selectedGroupID)
        data.defaultEditor = defaultEditor
        data.defaultOpenInNewWindow = defaultOpenInNewWindow
        return data
    }

    func setCardColor(_ color: CardColor, ids: Set<UUID>, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }),
              groups[index].cards.contains(where: { ids.contains($0.id) && $0.color != color }) else { return }
        recordUndo()
        for i in groups[index].cards.indices where ids.contains(groups[index].cards[i].id) { groups[index].cards[i].color = color }
        persist()
    }

    func updateConnection(_ id: UUID, in groupID: UUID, kind: ConnectionKind, label: String) {
        guard let g = groups.firstIndex(where: { $0.id == groupID }),
              let c = groups[g].connections.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        groups[g].connections[c].kind = kind
        groups[g].connections[c].label = String(label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        persist()
    }

    func setProjectOpening(_ id: UUID, editor: EditorChoice?, newWindow: Bool?) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        recordUndo()
        projects[index].editor = editor
        projects[index].openInNewWindow = newWindow
        persist()
    }

    func updateViewport(_ viewport: CanvasViewport, in groupID: UUID) {
        guard let index = groups.firstIndex(where: { $0.id == groupID }), groups[index].viewport != viewport else { return }
        groups[index].viewport = viewport
        if !needsRecovery { persistence.scheduleViewport(currentSnapshot) }
    }

    func relocateProject(_ id: UUID, to url: URL) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else {
            alertMessage = L10n.tr("请选择有效的文件夹。"); return
        }
        let path = url.standardizedFileURL.path
        guard !projects.contains(where: { $0.id != id && $0.folderPath == path }) else {
            alertMessage = L10n.tr("此文件夹已属于另一个项目。"); return
        }
        recordUndo()
        projects[index].folderPath = path
        gitStatuses[id] = nil
        persist()
        Task { await refreshGitStatuses() }
    }

    func refreshGitStatuses() async {
        guard !isRefreshingGit else { return }
        isRefreshingGit = true
        defer { isRefreshingGit = false }
        let snapshot = projects.map { ($0.id, $0.folderPath) }
        await withTaskGroup(of: (UUID, String, GitStatus, ProjectKind).self) { tasks in
            var remaining = snapshot.makeIterator()
            func enqueue(_ project: (UUID, String)) {
                tasks.addTask(priority: .utility) {
                    let url = URL(fileURLWithPath: project.1)
                    return (project.0, project.1, GitStatus.read(at: url), ProjectKind.detect(at: url))
                }
            }
            for _ in 0..<3 { if let project = remaining.next() { enqueue(project) } }
            while let (id, path, status, kind) = await tasks.next() {
                if projects.contains(where: { $0.id == id && $0.folderPath == path }) {
                    gitStatuses[id] = status
                    if projectKinds[id] != kind { projectKinds[id] = kind }
                }
                if !Task.isCancelled, let project = remaining.next() { enqueue(project) }
            }
        }
    }

    func exportGroup(_ id: UUID, to url: URL) {
        guard let group = groups.first(where: { $0.id == id }) else { return }
        let ids = Set(group.cards.compactMap(\.projectID))
        let data = ProjectCanvasData(projects: projects.filter { ids.contains($0.id) }, groups: [group], selectedGroupID: group.id)
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: url, options: .atomic)
        } catch { alertMessage = L10n.format("导出失败：%@", error.localizedDescription) }
    }

    func importGroups(from url: URL, pathFrom: String, pathTo: String) {
        do {
            let incoming = try CanvasStorage.decode(Data(contentsOf: url))
            guard !incoming.groups.isEmpty else { alertMessage = L10n.tr("文件中没有可导入的项目组。"); return }
            recordUndo()
            restoring = true
            var projectMap: [UUID: UUID] = [:]
            let source = pathFrom.isEmpty ? "" : URL(fileURLWithPath: pathFrom).standardizedFileURL.path
            let target = pathTo.isEmpty ? "" : URL(fileURLWithPath: pathTo).standardizedFileURL.path
            for var project in incoming.projects {
                if !source.isEmpty && !target.isEmpty && (project.folderPath == source || project.folderPath.hasPrefix(source + "/")) {
                    project.folderPath = target + project.folderPath.dropFirst(source.count)
                }
                if let existing = projects.first(where: { $0.folderPath == project.folderPath }) { projectMap[project.id] = existing.id }
                else {
                    let old = project.id; project.id = UUID(); projectMap[old] = project.id; projects.append(project)
                }
            }
            for var group in incoming.groups {
                group.id = UUID()
                var cardMap: [UUID: UUID] = [:]
                group.cards = group.cards.map { original in
                    var card = original; card.id = UUID(); cardMap[original.id] = card.id
                    card.projectID = original.projectID.flatMap { projectMap[$0] }
                    return card
                }
                group.connections = group.connections.map { original in
                    var edge = original; edge.id = UUID()
                    edge.fromCardID = cardMap[original.fromCardID]!
                    edge.toCardID = cardMap[original.toCardID]!
                    return edge
                }
                group.regions = group.regions.map { original in
                    var region = original; region.id = UUID()
                    region.cardIDs = Set(original.cardIDs.compactMap { cardMap[$0] })
                    return region
                }
                groups.append(group)
                selectedGroupID = group.id
            }
            restoring = false
            if needsRecovery { try persistence.replacePreservingOriginal(currentSnapshot); needsRecovery = false }
            else { persist() }
            Task { await refreshGitStatuses() }
        } catch { restoring = false; alertMessage = L10n.format("导入失败：%@", error.localizedDescription) }
    }

    func restoreBackup() {
        do {
            let data = try persistence.restoreBackup()
            undoStack.removeAll(); redoStack.removeAll()
            needsRecovery = false
            restore(data)
            Task { await refreshGitStatuses() }
        } catch { alertMessage = L10n.format("恢复失败：%@", error.localizedDescription) }
    }

    private func recordUndo() {
        undoStack.append(currentSnapshot)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        updateHistoryAvailability()
    }

    private func restore(_ snapshot: ProjectCanvasData, preservingUsage: Bool = false) {
        restoring = true
        let usage = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, ($0.lastOpenedAt, $0.openCount)) })
        projects = snapshot.projects.map { original in
            var project = original
            if preservingUsage, let current = usage[project.id],
               project.lastOpenedAt != current.0 || project.openCount != current.1 {
                project.lastOpenedAt = current.0
                project.openCount = current.1
            }
            return project
        }
        groups = snapshot.groups
        selectedGroupID = snapshot.selectedGroupID
        defaultEditor = snapshot.defaultEditor ?? .vscode
        defaultOpenInNewWindow = snapshot.defaultOpenInNewWindow ?? false
        restoring = false
        updateHistoryAvailability()
        persist()
    }

    private func updateHistoryAvailability() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }
}
