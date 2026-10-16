import AppKit

/// Drawn inside the dismissible blur panel, below the independently clickable cards.
final class DesktopConnectionView: NSView {
    private var connections: [DesktopSceneLayout.Connection] = []
    private var scale: CGFloat = 1
    private var showsLabels = true
    override var isFlipped: Bool { true }

    func update(connections: [DesktopSceneLayout.Connection], scale: CGFloat, showsLabels: Bool = true) {
        guard self.connections != connections || self.scale != scale || self.showsLabels != showsLabels else { return }
        self.connections = connections
        self.scale = scale
        self.showsLabels = showsLabels
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        for edge in connections {
            let color = NSColor.controlAccentColor
            color.setStroke()
            let line = NSBezierPath()
            line.move(to: edge.start)
            // NSBezierPath has cubic curves; convert the shared quadratic control point.
            line.curve(to: edge.end,
                       controlPoint1: CGPoint(x: edge.start.x + (edge.control.x - edge.start.x) * 2 / 3,
                                              y: edge.start.y + (edge.control.y - edge.start.y) * 2 / 3),
                       controlPoint2: CGPoint(x: edge.end.x + (edge.control.x - edge.end.x) * 2 / 3,
                                              y: edge.end.y + (edge.control.y - edge.end.y) * 2 / 3))
            line.lineWidth = max(1.5, 2 * scale)
            line.stroke()
            let angle = atan2(edge.end.y - edge.control.y, edge.end.x - edge.control.x)
            let arrowSize = max(7, 12 * scale)
            let arrow = NSBezierPath()
            arrow.move(to: edge.end)
            arrow.line(to: CGPoint(x: edge.end.x - cos(angle - .pi / 6) * arrowSize, y: edge.end.y - sin(angle - .pi / 6) * arrowSize))
            arrow.line(to: CGPoint(x: edge.end.x - cos(angle + .pi / 6) * arrowSize, y: edge.end.y - sin(angle + .pi / 6) * arrowSize))
            arrow.close()
            color.setFill()
            arrow.fill()
            guard showsLabels else { continue }
            let text = edge.label as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: max(10, 12 * scale), weight: .medium),
                .foregroundColor: NSColor.labelColor
            ]
            let size = text.size(withAttributes: attributes)
            let midpoint = CGPoint(x: (edge.start.x + 2 * edge.control.x + edge.end.x) / 4,
                                   y: (edge.start.y + 2 * edge.control.y + edge.end.y) / 4)
            let textRect = CGRect(x: midpoint.x - size.width / 2, y: midpoint.y - size.height - 4, width: size.width, height: size.height)
            NSColor.windowBackgroundColor.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: textRect.insetBy(dx: -4, dy: -2), xRadius: 4, yRadius: 4).fill()
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
