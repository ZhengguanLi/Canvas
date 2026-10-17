import SwiftUI

/// Individual Liquid Glass buttons floating over the canvas, without a shared backing card.
/// Liquid Glass follows the system's Reduce Transparency setting on its own.
struct CanvasFloatingControls: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.glass)
    }
}
