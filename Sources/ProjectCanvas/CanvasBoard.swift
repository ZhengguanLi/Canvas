import AppKit
import SwiftUI

struct CanvasBoard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var language = LanguageController.shared
    @ObservedObject var model: AppModel
    let group: ProjectGroup
    let zoom: Double
    let isEditing: Bool
    let snapToGrid: Bool
    @Binding var selectedCardIDs: Set<UUID>
    @Binding var selectedConnectionID: UUID?
    @Binding var isConnecting: Bool
    @Binding var firstConnectionCardID: UUID?
    let highlightDirection: Int
    let onOpenSettings: (Project) -> Void
    let onRelocate: (Project) -> Void
    var onOpenDetails: (Project) -> Void = { _ in }
    var onBackgroundSettings: (() -> Void)?
    var onAddFolders: (() -> Void)?
    var onShowAll: (() -> Void)?
    var minimumSize: CGSize = .zero
    var minimumHeight: CGFloat = 800
    @AppStorage(ClipboardAppearance.lastAllCardsColorKey) private var lastAllCardsColor = CardColor.neutral.rawValue
    var alignsToCards = true
    @State private var editingRegion: ProjectRegion?
    /// The note being edited in place, and its rich text while editing.
    @State private var inlineNoteID: UUID?
    @State private var noteDraft = AttributedString()
    @Environment(\.fontResolutionContext) private var fontContext
    @State private var hoveredCardID: UUID?
    @State private var selectionRect: CGRect?
    @State private var selectionAdds = false
    @State private var movingIDs: Set<UUID> = []
    @State private var dragOffset: CGSize = .zero
    @State private var alignmentGuides: [CanvasAlignment.Guide] = []

    @AppStorage(CanvasGeometry.cardScaleKey) private var cardScale = 1.0
    /// Cards are drawn at this scale about their centres; layout positions are unchanged.
    /// Read-only boards (the layout preview thumbnail) keep true card sizes so the layout stays legible.
    private var cardDisplayScale: Double {
        isEditing ? CanvasGeometry.clampedCardScale(cardScale) : 1
    }
    private var extent: CGSize { CanvasGeometry.extent(cards: group.cards, minimumSize: minimumSize, minimumHeight: minimumHeight, cardScale: cardDisplayScale) }
    private var related: Set<UUID> {
        guard highlightDirection != 0 else { return [] }
        return selectedCardIDs.union(group.relatedCardIDs(to: selectedCardIDs, upstream: highlightDirection < 0))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            drawing
                .contentShape(Rectangle())
                .contextMenu {
                    if let onBackgroundSettings {
                        CanvasBackgroundMenu(onCustomize: onBackgroundSettings, groupTheme: Binding(
                            get: { group.canvasTheme }, set: { model.setCanvasTheme($0, for: group.id) }))
                    }
                    if isEditing {
                        Menu(L10n.tr("所有卡片背景")) {
                            ForEach(CardColor.allCases) { color in
                                Button(color.title) {
                                    model.setCardColor(color, ids: Set(group.cards.map(\.id)), in: group.id)
                                    lastAllCardsColor = color.rawValue
                                }
                            }
                        }.disabled(group.cards.isEmpty)
                        ClipboardTextColorMenu()
                    }
                    if isEditing {
                        Button(L10n.tr("新建便签")) {
                            if let id = withAnimation(.spring(response: 0.35, dampingFraction: 0.7), { model.addNote(to: group.id) }) {
                                beginEditingNote(id, text: "")
                            }
                        }
                    }
                    if let onAddFolders {
                        Button(L10n.tr("添加文件夹（⇧⌘O）"), action: onAddFolders)
                    }
                    if let onShowAll {
                        Button(L10n.tr("适应视图"), action: onShowAll)
                    }
                }
                .gesture(SpatialTapGesture().onEnded { value in
                    guard isEditing else { return }
                    selectedConnectionID = group.showsConnections ? nearestConnection(to: value.location) : nil
                    selectedCardIDs.removeAll()
                })
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("board"))
                    .onChanged { value in
                        guard isEditing, !isConnecting else { return }
                        if selectionRect == nil { selectionAdds = CanvasInputSupport.currentEventExtendsSelection }
                        selectionRect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y), width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                    }
                    .onEnded { _ in
                        guard let rect = selectionRect else { return }
                        let ids = Set(group.cards.filter { rect.intersects(CanvasGeometry.cardFrame(x: $0.x, y: $0.y, scale: cardDisplayScale)) }.map(\.id))
                        selectedCardIDs = selectionAdds ? selectedCardIDs.union(ids) : ids
                        selectionRect = nil
                        selectedConnectionID = nil
                    })
            ForEach(group.regions) { region in
                if let presentation = regionBounds(region) {
                    let bounds = presentation.frame
                    RoundedRectangle(cornerRadius: 16).fill(region.color.wash.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(region.color.wash, lineWidth: 3))
                        .frame(width: bounds.width, height: bounds.height).position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                    Text(region.name).font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(region.color.wash, in: Capsule())
                        .lineLimit(1).frame(maxWidth: bounds.width)
                        .position(presentation.header)
                        .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                            guard isEditing, !isConnecting else { return }
                            movingIDs = region.cardIDs
                            let result = CanvasAlignment.resolve(cards: group.cards, movingIDs: movingIDs,
                                proposed: CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom),
                                zoom: zoom, enabled: alignsToCards)
                            dragOffset = result.offset
                            alignmentGuides = result.guides
                        }.onEnded { _ in
                            guard isEditing, !isConnecting else { return }
                            model.moveRegion(region.id, by: dragOffset, in: group.id)
                            movingIDs.removeAll(); dragOffset = .zero; alignmentGuides = []
                        })
                        .contextMenu {
                            Button(L10n.tr("编辑区域…")) { editingRegion = region }
                            Button(L10n.tr("选择区域成员")) { selectedCardIDs = region.cardIDs }
                            Button(L10n.tr("移除区域（保留卡片）"), role: .destructive) { model.removeRegion(region.id, in: group.id) }
                        }
                }
            }
            ForEach(group.cards) { card in
                Group {
                    if inlineNoteID == card.id {
                        NoteInlineEditor(text: $noteDraft, onCommit: commitNote)
                            .background(card.color.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2))
                    } else if let content = card.clipboard {
                        CanvasClipboardTile(content: content)
                            .simultaneousGesture(TapGesture(count: 2).onEnded {
                                if isEditing, case .note(let text) = content { beginEditingNote(card.id, text: text) }
                            })
                            .background(card.color.fill, in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selectedCardIDs.contains(card.id) || firstConnectionCardID == card.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedCardIDs.contains(card.id) || firstConnectionCardID == card.id ? 3 : 1))
                    } else if let project = model.project(for: card) {
                        tile(card, project: project)
                    }
                }
                        // Selection lifts the card slightly; new cards drop in from above.
                        .scaleEffect((selectedCardIDs.contains(card.id) && movingIDs.isEmpty ? 1.03 : 1) * cardDisplayScale)
                        .shadow(color: .black.opacity(selectedCardIDs.contains(card.id) ? 0.18 : 0), radius: 10, y: 5)
                        .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.75), value: selectedCardIDs.contains(card.id))
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(y: -18).combined(with: .scale(scale: 0.92)).combined(with: .opacity),
                            removal: .opacity))
                        .position(center(of: card))
                        .opacity(highlightDirection == 0 || selectedCardIDs.isEmpty || related.contains(card.id) ? 1 : 0.38)
                        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { value in
                                guard isEditing, !isConnecting else { return }
                                if movingIDs.isEmpty {
                                    movingIDs = selectedCardIDs.contains(card.id) ? selectedCardIDs : [card.id]
                                    selectedCardIDs = movingIDs
                                }
                                let result = CanvasAlignment.resolve(cards: group.cards, movingIDs: movingIDs,
                                    proposed: CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom),
                                    zoom: zoom, gridAnchor: snapToGrid ? CGPoint(x: card.x, y: card.y) : nil,
                                    enabled: alignsToCards)
                                dragOffset = result.offset
                                alignmentGuides = result.guides
                            }
                            .onEnded { _ in
                                guard !movingIDs.isEmpty else { return }
                                model.moveCards(ids: movingIDs, by: dragOffset, in: group.id)
                                movingIDs.removeAll()
                                dragOffset = .zero
                                alignmentGuides = []
                            }, including: isEditing && !isConnecting && inlineNoteID != card.id ? .all : .none)
                        .onTapGesture { handleCardClick(card, extendingSelection: CanvasInputSupport.currentEventExtendsSelection) }
                        .zIndex(inlineNoteID == card.id ? 1 : 0)
                        .contextMenu {
                            if let partner = selectedPartner(for: card) {
                                Button {
                                    connectSelectedCards(from: card.id)
                                } label: {
                                    Label(L10n.format("连接到 %@", cardTitle(partner)), systemImage: "arrow.right")
                                }
                                .disabled(group.connections.contains { $0.fromCardID == card.id && $0.toCardID == partner.id })
                                Divider()
                            }
                            if let project = model.project(for: card) { cardMenu(card, project: project) }
                            else if let content = card.clipboard {
                                if case .note(let text) = content {
                                    Button(L10n.tr("编辑便签…")) { beginEditingNote(card.id, text: text) }
                                }
                                Button(L10n.tr("复制内容")) { model.copyClipboardContent(content) }
                                Menu(L10n.tr("卡片背景")) {
                                    ForEach(CardColor.allCases) { color in
                                        Button(color.title) { model.setCardColor(color, ids: selectedCardIDs.contains(card.id) ? selectedCardIDs : [card.id], in: group.id) }
                                    }
                                }
                                Button(L10n.tr("从此组移除"), role: .destructive) { model.removeCard(card.id, from: group.id) }
                            }
                        }
            }
        }
        .frame(width: extent.width, height: extent.height, alignment: .topLeading)
        .background {
            if isEditing {
                CanvasInputSupport(onSelectAll: handleSelectAll, onKey: handleKey).allowsHitTesting(false)
            }
        }
        .sheet(item: $editingRegion) { RegionEditorView(model: model, groupID: group.id, cardIDs: $0.cardIDs, region: $0) }
        .coordinateSpace(name: "board")
        .scaleEffect(zoom, anchor: .topLeading)
        .frame(width: extent.width * zoom, height: extent.height * zoom, alignment: .topLeading)
    }

    private var drawing: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 16.0, through: size.width, by: 32) {
                for y in stride(from: 16.0, through: size.height, by: 32) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                }
            }
            context.fill(dots, with: .color(.secondary.opacity(0.25)))
            if group.showsConnections {
                let cards = Dictionary(uniqueKeysWithValues: group.cards.map { ($0.id, $0) })
                for edge in group.connections {
                    guard let from = cards[edge.fromCardID], let to = cards[edge.toCardID] else { continue }
                    let a = center(of: from), b = center(of: to)
                    let start = CanvasGeometry.edgePoint(from: b, to: a, scale: cardDisplayScale)
                    let end = CanvasGeometry.edgePoint(from: a, to: b, scale: cardDisplayScale)
                    let emphasized = edge.id == selectedConnectionID
                    let active = highlightDirection == 0 || selectedCardIDs.isEmpty || (related.contains(from.id) && related.contains(to.id))
                    let color = emphasized ? Color.orange : Color.accentColor.opacity(active ? 0.58 : 0.08)
                    // Reciprocal relationships use opposite curves to keep both labels selectable.
                    let reciprocal = group.connections.contains { $0.fromCardID == to.id && $0.toCardID == from.id }
                    let dx = end.x - start.x, dy = end.y - start.y
                    let length = max(1, hypot(dx, dy))
                    let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * (reciprocal ? 32 : 0), y: (start.y + end.y) / 2 + dx / length * (reciprocal ? 32 : 0))
                    var path = Path()
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                    context.stroke(path, with: .color(color), lineWidth: emphasized ? 3.5 : 1.6)
                    let angle = atan2(end.y - control.y, end.x - control.x)
                    var arrow = Path()
                    arrow.move(to: end)
                    arrow.addLine(to: CGPoint(x: end.x - cos(angle - .pi / 6) * 12, y: end.y - sin(angle - .pi / 6) * 12))
                    arrow.addLine(to: CGPoint(x: end.x - cos(angle + .pi / 6) * 12, y: end.y - sin(angle + .pi / 6) * 12))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(color))
                    let text = edge.label.flatMap { $0.isEmpty ? nil : $0 }.map { "\(edge.kind.title) · \($0)" } ?? edge.kind.title
                    let midpoint = CGPoint(x: (start.x + 2 * control.x + end.x) / 4, y: (start.y + 2 * control.y + end.y) / 4)
                    let labelColor = emphasized ? Color.orange : Color.primary.opacity(active ? 0.76 : 0.35)
                    let label = context.resolve(Text(text)
                        .font(.system(size: 10, weight: emphasized ? .semibold : .medium))
                        .foregroundColor(labelColor))
                    let labelSize = label.measure(in: CGSize(width: 10000, height: 10000))
                    let labelFrame = CGRect(x: midpoint.x - labelSize.width / 2 - 7,
                        y: midpoint.y - 10 - labelSize.height / 2 - 4, width: labelSize.width + 14, height: labelSize.height + 8)
                    let capsule = Path(roundedRect: labelFrame, cornerSize: CGSize(width: labelFrame.height / 2, height: labelFrame.height / 2))
                    context.fill(capsule, with: .color(Color(nsColor: .windowBackgroundColor).opacity(active ? 0.92 : 0.7)))
                    context.stroke(capsule, with: .color(Color.primary.opacity(emphasized ? 0.14 : 0.07)), lineWidth: 0.7)
                    context.draw(label, at: CGPoint(x: midpoint.x, y: midpoint.y - 10))
                }
            }
            for guide in alignmentGuides {
                var line = Path()
                line.move(to: guide.start)
                line.addLine(to: guide.end)
                context.stroke(line, with: .color(.pink.opacity(0.9)),
                    style: StrokeStyle(lineWidth: 1 / zoom, dash: [4 / zoom, 3 / zoom]))
            }
            if let selectionRect {
                let path = Path(selectionRect)
                context.fill(path, with: .color(.accentColor.opacity(0.12)))
                context.stroke(path, with: .color(.accentColor), lineWidth: 1)
            }
        }
        .background(CanvasBackgroundView(theme: group.canvasTheme))
    }

    private func regionBounds(_ region: ProjectRegion) -> (frame: CGRect, header: CGPoint)? {
        let members = group.cards.filter { region.cardIDs.contains($0.id) }
        let halfWidth = CanvasGeometry.cardSize.width / 2 * cardDisplayScale
        let halfHeight = CanvasGeometry.cardSize.height / 2 * cardDisplayScale
        guard let minX = members.map({ center(of: $0).x - halfWidth }).min(),
              let minY = members.map({ center(of: $0).y - halfHeight }).min(),
              let maxX = members.map({ center(of: $0).x + halfWidth }).max(),
              let maxY = members.map({ center(of: $0).y + halfHeight }).max() else { return nil }
        return CanvasGeometry.regionPresentation(around: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func center(of card: ProjectCard) -> CGPoint {
        CGPoint(x: card.x + 105 + (movingIDs.contains(card.id) ? dragOffset.width : 0), y: card.y + 50 + (movingIDs.contains(card.id) ? dragOffset.height : 0))
    }

    /// Shown while hovering a project card, so common actions skip the context menu.
    private func quickActions(_ project: Project) -> some View {
        HStack(spacing: 2) {
            quickAction("arrow.up.forward.app", L10n.tr("打开项目")) { model.openProject(project) }
            quickAction("terminal", L10n.tr("在终端中打开")) { model.openProject(project, editorOverride: .terminal) }
            quickAction("folder", L10n.tr("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([project.folderURL]) }
            quickAction("doc.on.doc", L10n.tr("复制路径")) {
                NSPasteboard.general.clearContents(); NSPasteboard.general.setString(project.folderPath, forType: .string)
            }
        }
        .padding(3)
        .glassEffect(.regular.interactive(), in: Capsule())
        .padding(5)
    }

    private func quickAction(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 20, height: 18)
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }

    /// Status dot plus branch; long branches truncate in the middle so both ends stay readable.
    private func gitLine(_ status: GitStatus) -> some View {
        HStack(spacing: 4) {
            Circle().fill(status.health == .clean ? Color.green : status.health == .changed ? Color.orange : Color.gray)
                .frame(width: 6, height: 6)
            if status.health == .unavailable {
                Text(status.summary).lineLimit(1)
            } else {
                Text(status.branch).lineLimit(1).truncationMode(.middle)
                Text("· " + status.changeSummary).lineLimit(1).fixedSize()
            }
        }
        .font(.system(size: 10)).foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    private func tile(_ card: ProjectCard, project: Project) -> some View {
        VStack(spacing: 7) {
            Text(card.customName ?? project.folderName)
                .font(.system(size: 15, weight: .semibold)).lineLimit(2)
            if !project.tags.isEmpty {
                Text(project.tags.map { "#" + $0 }.joined(separator: " "))
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            if let status = model.gitStatuses[project.id] { gitLine(status) }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(width: 210, height: 100)
        .overlay(alignment: .topLeading) {
            Image(systemName: (model.projectKinds[project.id] ?? .folder).symbol)
                .font(.system(size: 11)).foregroundStyle(.secondary).padding(9)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            if hoveredCardID == card.id && movingIDs.isEmpty && !isConnecting {
                quickActions(project).transition(.opacity)
            }
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) {
                if inside { hoveredCardID = card.id } else if hoveredCardID == card.id { hoveredCardID = nil }
            }
        }
        .background(card.color.fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(firstConnectionCardID == card.id ? Color.orange : selectedCardIDs.contains(card.id) ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedCardIDs.contains(card.id) || firstConnectionCardID == card.id ? 3 : 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .help(project.folderPath + "\n" + L10n.tr("拖动移动；⌘ / ⇧ 点击多选"))
        .accessibilityLabel(card.customName ?? project.folderName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { handleCardClick(card, extendingSelection: CanvasInputSupport.currentEventExtendsSelection) }
    }

    @ViewBuilder private func cardMenu(_ card: ProjectCard, project: Project) -> some View {
        Button(L10n.tr("打开项目")) { model.openProject(project) }
        Button(L10n.tr("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([project.folderURL]) }
        Button(L10n.tr("复制路径")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(project.folderPath, forType: .string) }
        ProjectRunMenu(model: model, project: project)
        Button(L10n.tr("项目详情…")) { onOpenDetails(project) }
        Button(L10n.tr("打开方式…")) { onOpenSettings(project) }
        Button(L10n.tr("重新定位文件夹…")) { onRelocate(project) }
        Divider()
        Menu(L10n.tr("卡片背景")) {
            ForEach(CardColor.allCases) { color in
                Button(color.title) { model.setCardColor(color, ids: selectedCardIDs.contains(card.id) ? selectedCardIDs : [card.id], in: group.id) }
            }
        }
        Button(L10n.tr("重命名卡片")) { model.beginRenaming(cardID: card.id) }
        Button(L10n.tr("从此组移除"), role: .destructive) { model.removeCard(card.id, from: group.id) }
    }

    private func selectedPartner(for card: ProjectCard) -> ProjectCard? {
        guard selectedCardIDs.count == 2, selectedCardIDs.contains(card.id) else { return nil }
        return group.cards.first { $0.id != card.id && selectedCardIDs.contains($0.id) }
    }

    private func cardTitle(_ card: ProjectCard) -> String {
        card.customName ?? model.project(for: card)?.folderName ?? card.clipboard?.title ?? ""
    }

    /// Arrow keys move the selection, Return opens (or edits a note), ⌘D duplicates note and clipboard cards.
    func handleKey(_ key: CanvasInputSupport.Key) -> Bool {
        guard isEditing, !isConnecting else { return false }
        let current = selectedCardIDs.count == 1 ? group.cards.first { selectedCardIDs.contains($0.id) } : nil
        switch key {
        case .arrow(let direction):
            guard !group.cards.isEmpty else { return false }
            if let next = CanvasNavigation.next(from: current, direction: direction, in: group.cards) {
                selectedCardIDs = [next.id]
                selectedConnectionID = nil
            }
            return true
        case .open:
            guard let current else { return false }
            if let project = model.project(for: current) { model.openProject(project) }
            else if case .note(let text) = current.clipboard { beginEditingNote(current.id, text: text) }
            else if let content = current.clipboard { model.copyClipboardContent(content) }
            return true
        case .duplicate:
            let copies = withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { model.duplicateCards(selectedCardIDs, in: group.id) }
            if !copies.isEmpty { selectedCardIDs = copies }
            return !copies.isEmpty
        }
    }

    func beginEditingNote(_ id: UUID, text: String) {
        if inlineNoteID != nil { commitNote() }
        noteDraft = NoteMarkdown.attributed(from: text)
        selectedCardIDs = [id]
        inlineNoteID = id
    }

    /// Saves the in-place edit back as Markdown; fonts set by ⌘B / ⌘I are read through the environment.
    func commitNote() {
        guard let id = inlineNoteID else { return }
        inlineNoteID = nil
        let markdown = NoteMarkdown.markdown(from: noteDraft) { [fontContext] font in
            let resolved = font.resolve(in: fontContext)
            return (resolved.isBold, resolved.isItalic, resolved.isMonospaced)
        }
        model.updateNote(id, text: markdown, in: group.id)
    }

    func handleSelectAll() {
        guard isEditing else { return }
        selectedCardIDs = Set(group.cards.map(\.id))
        selectedConnectionID = nil
        isConnecting = false
        firstConnectionCardID = nil
    }

    func connectSelectedCards(from cardID: UUID) {
        guard let card = group.cards.first(where: { $0.id == cardID }),
              let partner = selectedPartner(for: card) else { return }
        model.connectCards(cardID, partner.id, in: group.id)
        selectedConnectionID = model.groups.first(where: { $0.id == group.id })?.connections
            .first(where: { $0.fromCardID == cardID && $0.toCardID == partner.id })?.id
        isConnecting = false
        firstConnectionCardID = nil
    }

    func handleCardClick(_ card: ProjectCard, extendingSelection: Bool) {
        if isConnecting {
            if let first = firstConnectionCardID {
                model.connectCards(first, card.id, in: group.id)
                firstConnectionCardID = nil
                isConnecting = false
            } else { firstConnectionCardID = card.id }
        } else if isEditing {
            if extendingSelection {
                if selectedCardIDs.contains(card.id) { selectedCardIDs.remove(card.id) }
                else { selectedCardIDs.insert(card.id) }
            } else { selectedCardIDs = [card.id] }
            selectedConnectionID = nil
        }
    }

    private func nearestConnection(to point: CGPoint) -> UUID? {
        let cards = Dictionary(uniqueKeysWithValues: group.cards.map { ($0.id, $0) })
        return group.connections.compactMap { edge -> (UUID, CGFloat)? in
            guard let from = cards[edge.fromCardID], let to = cards[edge.toCardID] else { return nil }
            let a = center(of: from), b = center(of: to)
            let start = CanvasGeometry.edgePoint(from: b, to: a, scale: cardDisplayScale)
            let end = CanvasGeometry.edgePoint(from: a, to: b, scale: cardDisplayScale)
            let dx = end.x - start.x, dy = end.y - start.y
            let length = max(1, hypot(dx, dy))
            let reciprocal = group.connections.contains { $0.fromCardID == to.id && $0.toCardID == from.id }
            let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * (reciprocal ? 32 : 0), y: (start.y + end.y) / 2 + dx / length * (reciprocal ? 32 : 0))
            let distance = (0...50).map { step -> CGFloat in
                let t = CGFloat(step) / 50, u = 1 - t
                return hypot(point.x - (u*u*start.x + 2*u*t*control.x + t*t*end.x), point.y - (u*u*start.y + 2*u*t*control.y + t*t*end.y))
            }.min() ?? .infinity
            return distance <= 16 / zoom ? (edge.id, distance) : nil
        }.min(by: { $0.1 < $1.1 })?.0
    }
}
