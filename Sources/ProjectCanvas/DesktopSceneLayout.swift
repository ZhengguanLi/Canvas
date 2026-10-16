import Foundation

/// Cards and connections share one transform from canvas coordinates to the chosen display.
struct DesktopSceneLayout {
    struct Connection: Equatable {
        let start: CGPoint
        let control: CGPoint
        let end: CGPoint
        let label: String
    }

    let scale: CGFloat
    private(set) var cardFrames: [UUID: CGRect]
    private let visibleFrame: CGRect
    private let screenFrame: CGRect
    private let canvasOrigin: CGPoint
    private let displayLeft: CGFloat
    private let displayTop: CGFloat

    init(cards: [ProjectCard], screenFrame: CGRect, visibleFrame: CGRect, requestedScale: CGFloat = 1) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame
        let minX = cards.map(\.x).min() ?? 0
        let minY = cards.map(\.y).min() ?? 0
        let width = max(1, (cards.map { $0.x + 210 }.max() ?? minX) - minX)
        let height = max(1, (cards.map { $0.y + 100 }.max() ?? minY) - minY)
        let requestedScale = requestedScale.isFinite ? min(1.5, max(0.6, requestedScale)) : 1
        let scale = min(requestedScale, visibleFrame.width / width, visibleFrame.height / height)
        self.scale = scale
        canvasOrigin = CGPoint(x: minX, y: minY)
        let left = visibleFrame.minX + (visibleFrame.width - width * scale) / 2
        let top = visibleFrame.maxY - (visibleFrame.height - height * scale) / 2
        displayLeft = left
        displayTop = top
        cardFrames = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, CGRect(x: left + (card.x - minX) * scale,
                             y: top - (card.y - minY + 100) * scale,
                             width: 210 * scale, height: 100 * scale))
        })
    }

    /// Update positions without refitting or recentering a scene during a desktop session.
    func updating(cards: [ProjectCard]) -> Self {
        var updated = self
        updated.cardFrames = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, CGRect(x: displayLeft + (card.x - canvasOrigin.x) * scale,
                             y: displayTop - (card.y - canvasOrigin.y + 100) * scale,
                             width: 210 * scale, height: 100 * scale))
        })
        return updated
    }

    func dragPosition(for card: ProjectCard, screenDelta: CGSize) -> CGPoint {
        guard scale > 0, screenDelta.width.isFinite, screenDelta.height.isFinite,
              let frame = cardFrames[card.id] else { return CGPoint(x: card.x, y: card.y) }
        let dx = min(visibleFrame.maxX - frame.maxX, max(visibleFrame.minX - frame.minX, screenDelta.width))
        let dy = min(visibleFrame.maxY - frame.maxY, max(visibleFrame.minY - frame.minY, screenDelta.height))
        return CGPoint(x: max(20, card.x + dx / scale), y: max(20, card.y - dy / scale))
    }

    func connections(in group: ProjectGroup) -> [Connection] {
        guard group.showsConnections else { return [] }
        let cards = Dictionary(uniqueKeysWithValues: group.cards.map { ($0.id, $0) })
        return group.connections.compactMap { edge in
            guard let from = cards[edge.fromCardID], let to = cards[edge.toCardID],
                  cardFrames[from.id] != nil, cardFrames[to.id] != nil else { return nil }
            let a = CGPoint(x: from.x + 105, y: from.y + 50)
            let b = CGPoint(x: to.x + 105, y: to.y + 50)
            let start = CanvasGeometry.edgePoint(from: b, to: a)
            let end = CanvasGeometry.edgePoint(from: a, to: b)
            let dx = end.x - start.x, dy = end.y - start.y
            let length = max(1, hypot(dx, dy))
            let reciprocal = group.connections.contains { $0.fromCardID == to.id && $0.toCardID == from.id }
            let control = CGPoint(x: (start.x + end.x) / 2 - dy / length * (reciprocal ? 32 : 0),
                                  y: (start.y + end.y) / 2 + dx / length * (reciprocal ? 32 : 0))
            let label = edge.label.flatMap { $0.isEmpty ? nil : $0 }.map { "\(edge.kind.title) · \($0)" } ?? edge.kind.title
            return Connection(start: localPoint(start), control: localPoint(control), end: localPoint(end), label: label)
        }
    }

    private func localPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: displayLeft - screenFrame.minX + (point.x - canvasOrigin.x) * scale,
                y: screenFrame.maxY - displayTop + (point.y - canvasOrigin.y) * scale)
    }
}
