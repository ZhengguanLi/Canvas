import Foundation

/// Coordinates are always stored in unscaled canvas points.
enum CanvasGeometry {
    static let cardSize = CGSize(width: 210, height: 100)

    static func regionPresentation(around cards: CGRect) -> (frame: CGRect, header: CGPoint) {
        // Near the canvas top, put the handle below its members instead of moving saved cards.
        let headerBelow = cards.minY < 42
        let top = max(0, cards.minY - (headerBelow ? 16 : 42))
        let bottom = cards.maxY + (headerBelow ? 42 : 16)
        let left = max(0, cards.minX - 16)
        let frame = CGRect(x: left, y: top, width: cards.maxX + 16 - left, height: bottom - top)
        return (frame, CGPoint(x: frame.midX, y: headerBelow ? bottom - 18 : top + 18))
    }

    static func extent(cards: [ProjectCard]) -> CGSize {
        CGSize(width: max(1200, (cards.map(\.x).max() ?? 0) + 330),
               height: max(800, (cards.map(\.y).max() ?? 0) + 220))
    }

    static func clampedOffset(_ proposed: CGSize, cards: [ProjectCard]) -> CGSize {
        CGSize(width: max(proposed.width, 20 - (cards.map(\.x).min() ?? 20)),
               height: max(proposed.height, 20 - (cards.map(\.y).min() ?? 20)))
    }

    static func edgePoint(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return end }
        let factor = min(dx == 0 ? .infinity : 105 / abs(dx), dy == 0 ? .infinity : 50 / abs(dy))
        return CGPoint(x: end.x - dx * factor, y: end.y - dy * factor)
    }
}
