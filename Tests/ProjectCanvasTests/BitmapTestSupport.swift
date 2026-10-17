import AppKit

extension NSBitmapImageRep {
    /// Samples by view point, not pixel: `cacheDisplay` renders at the screen's backing scale (2x on Retina).
    func color(atPoint point: CGPoint, in bounds: CGRect) -> NSColor? {
        colorAt(x: Int(point.x * CGFloat(pixelsWide) / bounds.width),
                y: Int(point.y * CGFloat(pixelsHigh) / bounds.height))
    }
}
