import Foundation

/// Coordinates are always stored in unscaled canvas points.
enum CanvasGeometry {
    static let cardSize = CGSize(width: 210, height: 100)

    /// Card size preference: cards are drawn larger about their centres; positions never change.
    static let cardScaleKey = "cardScale"
    static let cardScaleRange = 1.0...2.0

    static func clampedCardScale(_ value: Double) -> Double {
        value.isFinite ? min(cardScaleRange.upperBound, max(cardScaleRange.lowerBound, value)) : 1
    }

    /// The card's drawn rectangle in canvas points for a given display scale.
    static func cardFrame(x: Double, y: Double, scale: Double) -> CGRect {
        let size = CGSize(width: cardSize.width * scale, height: cardSize.height * scale)
        return CGRect(x: x + (cardSize.width - size.width) / 2, y: y + (cardSize.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    static func positionForDrop(at point: CGPoint, zoom: Double, scrollOffset: CGPoint = .zero) -> CGPoint {
        guard zoom.isFinite, zoom > 0, point.x.isFinite, point.y.isFinite, scrollOffset.x.isFinite, scrollOffset.y.isFinite else { return CGPoint(x: 20, y: 20) }
        return CGPoint(x: max(20, (point.x + scrollOffset.x) / zoom - cardSize.width / 2),
                       y: max(20, (point.y + scrollOffset.y) / zoom - cardSize.height / 2))
    }

    static func regionPresentation(around cards: CGRect) -> (frame: CGRect, header: CGPoint) {
        // Near the canvas top, put the handle below its members instead of moving saved cards.
        let headerBelow = cards.minY < 42
        let top = max(0, cards.minY - (headerBelow ? 16 : 42))
        let bottom = cards.maxY + (headerBelow ? 42 : 16)
        let left = max(0, cards.minX - 16)
        let frame = CGRect(x: left, y: top, width: cards.maxX + 16 - left, height: bottom - top)
        return (frame, CGPoint(x: frame.midX, y: headerBelow ? bottom - 18 : top + 18))
    }

    /// `minimumHeight` is 0 where the caller sizes the canvas to its viewport, so it only scrolls when cards overflow.
    /// Larger drawn cards (`cardScale`) widen the margin so their far edges stay reachable.
    static func extent(cards: [ProjectCard], minimumSize: CGSize = .zero, minimumHeight: CGFloat = 800, cardScale: Double = 1) -> CGSize {
        let half = CGSize(width: cardSize.width / 2, height: cardSize.height / 2)
        return CGSize(width: max(1200, minimumSize.width, (cards.map(\.x).max() ?? 0) + half.width * (1 + cardScale) + 120),
                      height: max(minimumHeight, minimumSize.height, (cards.map(\.y).max() ?? 0) + half.height * (1 + cardScale) + 120))
    }

    static func clampedOffset(_ proposed: CGSize, cards: [ProjectCard]) -> CGSize {
        CGSize(width: max(proposed.width, 20 - (cards.map(\.x).min() ?? 20)),
               height: max(proposed.height, 20 - (cards.map(\.y).min() ?? 20)))
    }

    static func edgePoint(from start: CGPoint, to end: CGPoint, scale: Double = 1) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        guard dx != 0 || dy != 0 else { return end }
        let halfWidth = cardSize.width / 2 * scale, halfHeight = cardSize.height / 2 * scale
        let factor = min(dx == 0 ? .infinity : halfWidth / abs(dx), dy == 0 ? .infinity : halfHeight / abs(dy))
        return CGPoint(x: end.x - dx * factor, y: end.y - dy * factor)
    }
}
