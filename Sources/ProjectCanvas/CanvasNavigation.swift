import Foundation

/// Picks the card to select when an arrow key is pressed on the canvas.
enum CanvasNavigation {
    static func next(from current: ProjectCard?, direction: CanvasInputSupport.Direction, in cards: [ProjectCard]) -> ProjectCard? {
        guard let current else {
            return cards.min { ($0.y, $0.x) < ($1.y, $1.x) }
        }
        // Distance along the arrow plus a heavier penalty for drifting sideways.
        let scored = cards.compactMap { card -> (ProjectCard, Double)? in
            guard card.id != current.id else { return nil }
            let dx = card.x - current.x, dy = card.y - current.y
            let (along, across): (Double, Double) = switch direction {
            case .left: (-dx, dy)
            case .right: (dx, dy)
            case .up: (-dy, dx)
            case .down: (dy, dx)
            }
            guard along > 1 else { return nil }
            return (card, along + 2 * abs(across))
        }
        return scored.min { $0.1 < $1.1 }?.0
    }
}
