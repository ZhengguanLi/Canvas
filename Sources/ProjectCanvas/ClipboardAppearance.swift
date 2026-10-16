import Foundation

/// Shared sizing keeps the clipboard rows and their desktop panel in sync.
struct ClipboardAppearance {
    static let imageScaleKey = "clipboardImageScale"
    static let textSizeKey = "clipboardTextSize"
    let imageScale: Double
    let textSize: Double

    init(imageScale: Double = 1.25, textSize: Double = 14) {
        self.imageScale = imageScale.isFinite ? min(2, max(1, imageScale)) : 1.25
        self.textSize = textSize.isFinite ? min(24, max(11, textSize)) : 14
    }

    static func load(from preferences: UserDefaults = .standard) -> Self {
        Self(imageScale: preferences.object(forKey: imageScaleKey) as? Double ?? 1.25,
             textSize: preferences.object(forKey: textSizeKey) as? Double ?? 14)
    }

    var imageRowHeight: Double { 80 * imageScale + ClipboardClotheslineGeometry.hangingClearance }
    var textRowHeight: Double { 80 * textSize / 11 + ClipboardClotheslineGeometry.hangingClearance }
    var shelfHeight: Double { 64 + imageRowHeight + textRowHeight }
    var canvasClotheslineHeight: Double { 10 + imageRowHeight + textRowHeight }
}
