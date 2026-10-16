import Foundation

struct DesktopAppearance: Equatable {
    let blur: Double
    let dimming: Double
    let cardScale: Double
    let showsLabels: Bool
    let tintColor: BackgroundTintColor
    let tintOpacity: Double

    init(blur: Double = 1, dimming: Double = 0, cardScale: Double = 1, showsLabels: Bool = true,
         tintColor: BackgroundTintColor = .default, tintOpacity: Double = 0) {
        self.blur = blur.isFinite ? min(1, max(0, blur)) : 1
        self.dimming = dimming.isFinite ? min(0.8, max(0, dimming)) : 0
        self.cardScale = cardScale.isFinite ? min(1.5, max(0.6, cardScale)) : 1
        self.showsLabels = showsLabels
        let tint = BackgroundTint(color: tintColor, opacity: tintOpacity)
        self.tintColor = tint.color
        self.tintOpacity = tint.opacity
    }

    static func load(from preferences: UserDefaults = .standard) -> Self {
        let tint = BackgroundTint.loadShared(from: preferences)
        return Self(blur: preferences.object(forKey: "desktopBlur") as? Double ?? 1,
             dimming: preferences.object(forKey: "desktopDimming") as? Double ?? 0,
             cardScale: preferences.object(forKey: "desktopCardScale") as? Double ?? 1,
             showsLabels: preferences.object(forKey: "desktopLabels") as? Bool ?? true,
             tintColor: tint.color, tintOpacity: tint.opacity)
    }

    func save(to preferences: UserDefaults = .standard) {
        preferences.set(blur, forKey: "desktopBlur")
        preferences.set(dimming, forKey: "desktopDimming")
        preferences.set(cardScale, forKey: "desktopCardScale")
        preferences.set(showsLabels, forKey: "desktopLabels")
        BackgroundTint(color: tintColor, opacity: tintOpacity).saveShared(to: preferences)
    }
}
