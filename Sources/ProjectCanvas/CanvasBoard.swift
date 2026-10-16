import AppKit
import SwiftUI

struct CanvasBoard: View {
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
    @State private var editingRegion: ProjectRegion?
    @State private var selectionRect: CGRect?
    @State private var selectionAdds = false
    @State private var movingIDs: Set<UUID> = []
    @State private var dragOffset: CGSize = .zero

    private var extent: CGSize { CanvasGeometry.extent(cards: group.cards) }
    private var related: Set<UUID> {
        guard highlightDirection != 0 else { return [] }
        return selectedCardIDs.union(group.relatedCardIDs(to: selectedCardIDs, upstream: highlightDirection < 0))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            drawing
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in
                    guard isEditing else { return }
                    selectedConnectionID = group.showsConnections ? nearestConnection(to: value.location) : nil
                    selectedCardIDs.removeAll()
                })
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .named("board"))
                    .onChanged { value in
                        guard isEditing, !isConnecting else { return }
                        if selectionRect == nil { selectionAdds = NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.control) }
                        selectionRect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y), width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                    }
                    .onEnded { _ in
                        guard let rect = selectionRect else { return }
                        let ids = Set(group.cards.filter { rect.intersects(CGRect(origin: CGPoint(x: $0.x, y: $0.y), size: CanvasGeometry.cardSize)) }.map(\.id))
                        selectedCardIDs = selectionAdds ? selectedCardIDs.union(ids) : ids
                        selectionRect = nil
                        selectedConnectionID = nil
                    })
            ForEach(group.regions) { region in
                if let presentation = regionBounds(region) {
                    let bounds = presentation.frame
                    RoundedRectangle(cornerRadius: 16).fill(region.color.fill.opacity(0.35))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(region.color.fill, lineWidth: 3))
                        .frame(width: bounds.width, height: bounds.height).position(x: bounds.midX, y: bounds.midY)
                        .allowsHitTesting(false)
                    Text(region.name).font(.headline).padding(.horizontal, 10).padding(.vertical, 4)
                        .background(region.color.fill, in: Capsule())
                        .lineLimit(1).frame(maxWidth: bounds.width)
                        .position(presentation.header)
                        .gesture(DragGesture(coordinateSpace: .global).onChanged { value in
                            guard isEditing, !isConnecting else { return }
                            movingIDs = region.cardIDs
                            dragOffset = CanvasGeometry.clampedOffset(CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom), cards: group.cards.filter { region.cardIDs.contains($0.id) })
                        }.onEnded { _ in
                            guard isEditing, !isConnecting else { return }
                            model.moveRegion(region.id, by: dragOffset, in: group.id)
                            movingIDs.removeAll(); dragOffset = .zero
                        })
                        .contextMenu {
                            Button(L10n.tr("编辑区域…")) { editingRegion = region }
                            Button(L10n.tr("选择区域成员")) { selectedCardIDs = region.cardIDs }
                            Button(L10n.tr("移除区域（保留卡片）"), role: .destructive) { model.removeRegion(region.id, in: group.id) }
                        }
                }
            }
            ForEach(group.cards) { card in
                if let project = model.project(for: card) {
                    tile(card, project: project)
                        .position(center(of: card))
                        .opacity(highlightDirection == 0 || selectedCardIDs.isEmpty || related.contains(card.id) ? 1 : 0.3)
                        .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                            .onChanged { value in
                                guard isEditing, !isConnecting else { return }
                                if movingIDs.isEmpty {
                                    movingIDs = selectedCardIDs.contains(card.id) ? selectedCardIDs : [card.id]
                                    selectedCardIDs = movingIDs
                                }
                                var offset = CGSize(width: value.translation.width / zoom, height: value.translation.height / zoom)
                                if snapToGrid {
                                    offset.width = ((card.x + offset.width) / 32).rounded() * 32 - card.x
                                    offset.height = ((card.y + offset.height) / 32).rounded() * 32 - card.y
                                }
                                dragOffset = CanvasGeometry.clampedOffset(offset, cards: group.cards.filter { movingIDs.contains($0.id) })
                            }
                            .onEnded { _ in
                                guard !movingIDs.isEmpty else { return }
                                model.moveCards(ids: movingIDs, by: dragOffset, in: group.id)
                                movingIDs.removeAll()
                                dragOffset = .zero
                            }, including: isEditing && !isConnecting ? .all : .none)
                        .onTapGesture { tap(card, project: project) }
                        .contextMenu { cardMenu(card, project: project) }
                }
            }
        }
        .frame(width: extent.width, height: extent.height, alignment: .topLeading)
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
                    let start = CanvasGeometry.edgePoint(from: b, to: a)
                    let end = CanvasGeometry.edgePoint(from: a, to: b)
                    let emphasized = edge.id == selectedConnectionID
                    let active = highlightDirection == 0 || selectedCardIDs.isEmpty || (related.contains(from.id) && related.contains(to.id))
                    let color = emphasized ? Color.orange : Color.accentColor.opacity(active ? 0.8 : 0.15)
                    // Reciprocal relationships use opposite curves to keep both labels selectable.
                    let reciprocal = group.connections.contains { $0.fromCardID == to.id && $0.toCardID == from.id }
                    let dx = end.x - start.x, dy = end.y - start.y
                    let length = max(1, hypot(dx, dy))
                    let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * (reciprocal ? 32 : 0), y: (start.y + end.y) / 2 + dx / length * (reciprocal ? 32 : 0))
                    var path = Path()
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                    context.stroke(path, with: .color(color), lineWidth: emphasized ? 3.5 : 2)
                    let angle = atan2(end.y - control.y, end.x - control.x)
                    var arrow = Path()
                    arrow.move(to: end)
                    arrow.addLine(to: CGPoint(x: end.x - cos(angle - .pi / 6) * 12, y: end.y - sin(angle - .pi / 6) * 12))
                    arrow.addLine(to: CGPoint(x: end.x - cos(angle + .pi / 6) * 12, y: end.y - sin(angle + .pi / 6) * 12))
                    arrow.closeSubpath()
                    context.fill(arrow, with: .color(color))
                    let text = edge.label.flatMap { $0.isEmpty ? nil : $0 }.map { "\(edge.kind.title) · \($0)" } ?? edge.kind.title
                    let midpoint = CGPoint(x: (start.x + 2 * control.x + end.x) / 4, y: (start.y + 2 * control.y + end.y) / 4)
                    context.draw(Text(text).font(.caption).foregroundColor(color), at: CGPoint(x: midpoint.x, y: midpoint.y - 10))
                }
            }
            if let selectionRect {
                let path = Path(selectionRect)
                context.fill(path, with: .color(.accentColor.opacity(0.12)))
                context.stroke(path, with: .color(.accentColor), lineWidth: 1)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func regionBounds(_ region: ProjectRegion) -> (frame: CGRect, header: CGPoint)? {
        let members = group.cards.filter { region.cardIDs.contains($0.id) }
        guard let minX = members.map({ center(of: $0).x - 105 }).min(),
              let minY = members.map({ center(of: $0).y - 50 }).min(),
              let maxX = members.map({ center(of: $0).x + 105 }).max(),
              let maxY = members.map({ center(of: $0).y + 50 }).max() else { return nil }
        return CanvasGeometry.regionPresentation(around: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }

    private func center(of card: ProjectCard) -> CGPoint {
        CGPoint(x: card.x + 105 + (movingIDs.contains(card.id) ? dragOffset.width : 0), y: card.y + 50 + (movingIDs.contains(card.id) ? dragOffset.height : 0))
    }

    private func tile(_ card: ProjectCard, project: Project) -> some View {
        VStack(spacing: 7) {
            Text(card.customName ?? project.folderName)
                .font(.system(size: 15, weight: .semibold)).lineLimit(2)
            if let status = model.gitStatuses[project.id] {
                Text(status.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
        .frame(width: 210, height: 100)
        .background(card.color.fill, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(firstConnectionCardID == card.id ? Color.orange : selectedCardIDs.contains(card.id) ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedCardIDs.contains(card.id) || firstConnectionCardID == card.id ? 3 : 1))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .help(project.folderPath + "\n" + (isEditing ? L10n.tr("拖动移动；⇧ 点击多选") : L10n.tr("点击打开 · 右键设置")))
        .accessibilityLabel(card.customName ?? project.folderName)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { tap(card, project: project) }
    }

    @ViewBuilder private func cardMenu(_ card: ProjectCard, project: Project) -> some View {
        Button(L10n.tr("打开项目")) { model.openProject(project) }
        Button(L10n.tr("在 Finder 中显示")) { NSWorkspace.shared.activateFileViewerSelecting([project.folderURL]) }
        Button(L10n.tr("复制路径")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(project.folderPath, forType: .string) }
        Button(L10n.tr("备注与链接…")) { onOpenDetails(project) }
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

    private func tap(_ card: ProjectCard, project: Project) {
        if isConnecting {
            if let first = firstConnectionCardID {
                model.connectCards(first, card.id, in: group.id)
                firstConnectionCardID = nil
                isConnecting = false
            } else { firstConnectionCardID = card.id }
        } else if isEditing {
            if NSEvent.modifierFlags.contains(.shift) {
                if selectedCardIDs.contains(card.id) { selectedCardIDs.remove(card.id) }
                else { selectedCardIDs.insert(card.id) }
            } else { selectedCardIDs = [card.id] }
            selectedConnectionID = nil
        } else { model.openProject(project) }
    }

    private func nearestConnection(to point: CGPoint) -> UUID? {
        let cards = Dictionary(uniqueKeysWithValues: group.cards.map { ($0.id, $0) })
        return group.connections.compactMap { edge -> (UUID, CGFloat)? in
            guard let from = cards[edge.fromCardID], let to = cards[edge.toCardID] else { return nil }
            let a = center(of: from), b = center(of: to)
            let start = CanvasGeometry.edgePoint(from: b, to: a), end = CanvasGeometry.edgePoint(from: a, to: b)
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
