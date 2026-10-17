import Foundation

/// Alignment is calculated in canvas points, with a fixed on-screen snap distance.
enum CanvasAlignment {
    /// Shared by the main canvas and desktop cards so one toggle controls both.
    static let enabledKey = "alignsToCards"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    struct Guide: Equatable {
        let start: CGPoint
        let end: CGPoint
    }

    struct Result {
        let offset: CGSize
        let guides: [Guide]
    }

    private struct Match {
        let correction: CGFloat
        let coordinate: CGFloat
        let target: CGRect
    }

    /// `clampsToOrigin` keeps cards at x, y ≥ 20 on the main canvas. Desktop drags pass false:
    /// they may cross the origin, which `moveDesktopCard` absorbs by rebasing the group.
    static func resolve(cards: [ProjectCard], movingIDs: Set<UUID>, proposed: CGSize,
                        zoom: Double, gridAnchor: CGPoint? = nil, enabled: Bool = true,
                        clampsToOrigin: Bool = true) -> Result {
        let moving = cards.filter { movingIDs.contains($0.id) }
        guard !moving.isEmpty, zoom.isFinite, zoom > 0 else {
            return Result(offset: .zero, guides: [])
        }
        let raw = clampsToOrigin ? CanvasGeometry.clampedOffset(proposed, cards: moving) : proposed
        let bounds = moving.reduce(CGRect.null) { bounds, card in
            bounds.union(CGRect(x: card.x, y: card.y, width: 210, height: 100))
        }.offsetBy(dx: raw.width, dy: raw.height)
        let threshold = 6 / zoom
        var horizontal: Match?
        var vertical: Match?
        if enabled {
            for card in cards where !movingIDs.contains(card.id) {
                let target = CGRect(x: card.x, y: card.y, width: 210, height: 100)
                for source in [bounds.minX, bounds.midX, bounds.maxX] {
                    for destination in [target.minX, target.midX, target.maxX] {
                        let correction = destination - source
                        if abs(correction) <= threshold,
                           horizontal.map({ abs(correction) < abs($0.correction) }) ?? true {
                            horizontal = Match(correction: correction, coordinate: destination, target: target)
                        }
                    }
                }
                for source in [bounds.minY, bounds.midY, bounds.maxY] {
                    for destination in [target.minY, target.midY, target.maxY] {
                        let correction = destination - source
                        if abs(correction) <= threshold,
                           vertical.map({ abs(correction) < abs($0.correction) }) ?? true {
                            vertical = Match(correction: correction, coordinate: destination, target: target)
                        }
                    }
                }
            }
        }
        var offset = raw
        if let horizontal { offset.width += horizontal.correction }
        else if let gridAnchor { offset.width = ((gridAnchor.x + raw.width) / 32).rounded() * 32 - gridAnchor.x }
        if let vertical { offset.height += vertical.correction }
        else if let gridAnchor { offset.height = ((gridAnchor.y + raw.height) / 32).rounded() * 32 - gridAnchor.y }
        if clampsToOrigin { offset = CanvasGeometry.clampedOffset(offset, cards: moving) }
        let aligned = bounds.offsetBy(dx: offset.width - raw.width, dy: offset.height - raw.height)
        let padding = 12 / zoom
        var guides: [Guide] = []
        if let horizontal, abs(offset.width - raw.width - horizontal.correction) < 0.001 {
            guides.append(Guide(start: CGPoint(x: horizontal.coordinate, y: min(aligned.minY, horizontal.target.minY) - padding),
                                end: CGPoint(x: horizontal.coordinate, y: max(aligned.maxY, horizontal.target.maxY) + padding)))
        }
        if let vertical, abs(offset.height - raw.height - vertical.correction) < 0.001 {
            guides.append(Guide(start: CGPoint(x: min(aligned.minX, vertical.target.minX) - padding, y: vertical.coordinate),
                                end: CGPoint(x: max(aligned.maxX, vertical.target.maxX) + padding, y: vertical.coordinate)))
        }
        return Result(offset: offset, guides: guides)
    }
}
