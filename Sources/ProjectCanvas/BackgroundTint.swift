import Foundation

/// A fixed sRGB color keeps stored preferences independent of system appearance.
struct BackgroundTintColor: Equatable {
    private let value: UInt32
    static let `default` = BackgroundTintColor(hex: "#6B9BD2")!

    init?(hex: String) {
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        self.value = value
    }

    init(red: Double, green: Double, blue: Double) {
        func channel(_ component: Double) -> UInt32 {
            UInt32(((component.isFinite ? min(1, max(0, component)) : 0) * 255).rounded())
        }
        value = channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    var hex: String { String(format: "#%06X", value) }
    var red: Double { Double((value >> 16) & 255) / 255 }
    var green: Double { Double((value >> 8) & 255) / 255 }
    var blue: Double { Double(value & 255) / 255 }
}

struct BackgroundTint: Equatable {
    static let colorPreferenceKey = "backgroundTintColor"
    static let opacityPreferenceKey = "backgroundTintOpacity"
    let color: BackgroundTintColor
    let opacity: Double

    init(color: BackgroundTintColor = .default, opacity: Double = 0) {
        self.color = color
        self.opacity = opacity.isFinite ? min(0.8, max(0, opacity)) : 0
    }

    static func load(from preferences: UserDefaults = .standard, prefix: String) -> Self {
        Self(color: preferences.string(forKey: prefix + "TintColor").flatMap(BackgroundTintColor.init(hex:)) ?? .default,
             opacity: preferences.object(forKey: prefix + "TintOpacity") as? Double ?? 0)
    }

    func save(to preferences: UserDefaults = .standard, prefix: String) {
        preferences.set(color.hex, forKey: prefix + "TintColor")
        preferences.set(opacity, forKey: prefix + "TintOpacity")
    }

    static func loadShared(from preferences: UserDefaults = .standard) -> Self {
        migrateLegacyPreferences(from: preferences)
        return load(from: preferences, prefix: "background")
    }

    func saveShared(to preferences: UserDefaults = .standard) {
        save(to: preferences, prefix: "background")
    }

    static func migrateLegacyPreferences(from preferences: UserDefaults = .standard) {
        guard preferences.object(forKey: colorPreferenceKey) == nil,
              preferences.object(forKey: opacityPreferenceKey) == nil else { return }
        // Keep the user's canvas choice when the two older palettes disagree.
        let hasCanvasChoice = preferences.object(forKey: "canvasTintColor") != nil ||
            preferences.object(forKey: "canvasTintOpacity") != nil
        load(from: preferences, prefix: hasCanvasChoice ? "canvas" : "desktop").saveShared(to: preferences)
    }
}
