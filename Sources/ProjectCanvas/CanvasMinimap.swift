import SwiftUI

/// Scaled overview of the canvas. Click or drag to move the visible area.
/// World coordinates are unscaled canvas points with the clothesline band on top.
struct CanvasMinimap: View {
    let cards: [ProjectCard]
    let clotheslineHeight: Double
    let extent: CGSize
    let zoom: Double
    let viewport: CGSize
    @Binding var offset: CGPoint

    private static let maxSize = CGSize(width: 180, height: 120)

    private var world: CGSize { CGSize(width: extent.width, height: extent.height + clotheslineHeight) }
    private var scale: Double { min(Self.maxSize.width / world.width, Self.maxSize.height / world.height) }
    /// Content is centred horizontally when the window is wider than the zoomed canvas.
    private var horizontalInset: Double { max(0, (viewport.width - extent.width * zoom) / 2) }

    static func isUseful(extent: CGSize, clotheslineHeight: Double, zoom: Double, viewport: CGSize) -> Bool {
        extent.width * zoom > viewport.width + 1 || (extent.height + clotheslineHeight) * zoom > viewport.height + 1
    }

    var body: some View {
        let size = CGSize(width: world.width * scale, height: world.height * scale)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(Color.secondary.opacity(0.12))
                .frame(width: size.width, height: clotheslineHeight * scale)
            ForEach(cards) { card in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(card.color == .neutral ? Color.secondary.opacity(0.55) : Color(nsColor: card.color.nsColor).opacity(0.8))
                    .frame(width: CanvasGeometry.cardSize.width * scale, height: CanvasGeometry.cardSize.height * scale)
                    .offset(x: card.x * scale, y: (clotheslineHeight + card.y) * scale)
            }
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.accentColor, lineWidth: 1.5)
                .background(RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.08)))
                .frame(width: min(size.width, viewport.width / zoom * scale), height: min(size.height, viewport.height / zoom * scale))
                .offset(x: max(0, (offset.x - horizontalInset) / zoom * scale), y: offset.y / zoom * scale)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
            offset = Self.offset(centeredOn: CGPoint(x: (value.location.x - 6) / scale, y: (value.location.y - 6) / scale),
                                 zoom: zoom, viewport: viewport, world: world, inset: horizontalInset)
        })
        .help(L10n.tr("点击或拖动以移动视图"))
        .accessibilityLabel(L10n.tr("画布小地图"))
    }

    /// Scroll offset that centres `point` (world coordinates), clamped to the scrollable range.
    static func offset(centeredOn point: CGPoint, zoom: Double, viewport: CGSize, world: CGSize, inset: Double = 0) -> CGPoint {
        let maxX = max(0, world.width * zoom + 2 * inset - viewport.width)
        let maxY = max(0, world.height * zoom - viewport.height)
        return CGPoint(x: min(maxX, max(0, point.x * zoom + inset - viewport.width / 2)),
                       y: min(maxY, max(0, point.y * zoom - viewport.height / 2)))
    }
}
