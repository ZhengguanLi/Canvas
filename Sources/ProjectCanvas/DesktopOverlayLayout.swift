import Foundation

/// AppKit screen coordinates, with a reserved interactive shelf above the cards.
struct DesktopOverlayLayout {
    let shelf: CGRect
    let cards: CGRect

    init(visibleFrame: CGRect, expanded: Bool, fullScreen: Bool = false, fullWidth: Bool = false, shelfHeight requestedHeight: Double = 224, visible: Bool = true) {
        let inset = visibleFrame.insetBy(dx: 24, dy: 24)
        guard visible else {
            shelf = .zero
            cards = inset
            return
        }
        let shelfHeight = min(expanded ? requestedHeight : 50.0, max(50, inset.height - 100))
        let width = fullWidth ? inset.width : min(1100, inset.width)
        let compactShelf = CGRect(x: inset.midX - width / 2, y: inset.maxY - shelfHeight, width: width, height: shelfHeight)
        shelf = fullScreen ? inset : compactShelf
        cards = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: max(1, compactShelf.minY - 24 - inset.minY))
    }
}
