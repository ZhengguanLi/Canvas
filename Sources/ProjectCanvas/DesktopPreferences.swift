import AppKit

/// Resolves a saved display identifier, falling back when that display is disconnected.
enum DesktopPreferences {
    static let screenIDKey = "desktopScreenID"

    static func identifier(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static var selectedScreen: NSScreen? {
        let savedID = UserDefaults.standard.string(forKey: screenIDKey) ?? ""
        return NSScreen.screens.first { !savedID.isEmpty && identifier(for: $0) == savedID }
            ?? NSScreen.main ?? NSScreen.screens.first
    }
}
