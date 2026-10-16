import Foundation

/// AppKit screen coordinates, with a reserved interactive shelf above the cards.
struct DesktopOverlayLayout {
    let shelf: CGRect
    let cards: CGRect

    init(visibleFrame: CGRect, expanded: Bool, fullScreen: Bool = false) {
        let inset = visibleFrame.insetBy(dx: 24, dy: 24)
        let shelfHeight = min(expanded ? 224.0 : 50.0, max(50, inset.height * 0.45))
        let width = min(1100, inset.width)
        let compactShelf = CGRect(x: inset.midX - width / 2, y: inset.maxY - shelfHeight, width: width, height: shelfHeight)
        shelf = fullScreen ? inset : compactShelf
        cards = CGRect(x: inset.minX, y: inset.minY, width: inset.width, height: max(1, compactShelf.minY - 16 - inset.minY))
    }
}
