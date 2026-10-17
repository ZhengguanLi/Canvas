import AppKit
import Carbon
import Combine

extension Notification.Name {
    /// Posted when the desktop shortcut changes or recording starts/stops, so it is re-registered.
    static let projectCanvasHotKeyChanged = Notification.Name("ProjectCanvasHotKeyChanged")
}

/// The global shortcut that shows or hides desktop cards.
struct HotKeyShortcut: Codable, Equatable {
    static let preferenceKey = "desktopToggleShortcut"
    static let `default` = HotKeyShortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command, .shift], key: "C")
    private static let allowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]

    var keyCode: UInt16
    private var modifierBits: UInt
    /// Display name of the key as it was typed, e.g. "C" or "Space".
    var key: String

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, key: String) {
        self.keyCode = keyCode
        self.modifierBits = modifiers.intersection(Self.allowedModifiers).rawValue
        self.key = key
    }

    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifierBits).intersection(Self.allowedModifiers) }

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.command) { result |= cmdKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.control) { result |= controlKey }
        return UInt32(result)
    }

    /// Standard macOS order: ⌃⌥⇧⌘ then the key.
    var displayString: String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "") +
            (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "") + key
    }

    /// A recorded key press becomes a shortcut only with ⌘, ⌃ or ⌥, so plain typing is never captured.
    static func from(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, characters: String?) -> HotKeyShortcut? {
        let flags = modifiers.intersection(allowedModifiers)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let key = keyName(keyCode: keyCode, characters: characters) else { return nil }
        return HotKeyShortcut(keyCode: keyCode, modifiers: flags, key: key)
    }

    private static let namedKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(keyCode: UInt16, characters: String?) -> String? {
        if keyCode == UInt16(kVK_Escape) { return nil }
        if let name = namedKeys[Int(keyCode)] { return name }
        guard let characters = characters?.trimmingCharacters(in: .whitespacesAndNewlines), !characters.isEmpty else { return nil }
        return characters.uppercased()
    }

    static func load(from preferences: UserDefaults = .standard) -> HotKeyShortcut {
        guard let data = preferences.data(forKey: preferenceKey),
              let shortcut = try? JSONDecoder().decode(HotKeyShortcut.self, from: data),
              !shortcut.modifiers.intersection([.command, .control, .option]).isEmpty else { return .default }
        return shortcut
    }

    func save(to preferences: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { preferences.set(data, forKey: Self.preferenceKey) }
        NotificationCenter.default.post(name: .projectCanvasHotKeyChanged, object: nil)
    }
}

/// Shared state between the shortcut recorder and the registration in DesktopDisplayController.
@MainActor
final class HotKeyStatus: ObservableObject {
    static let shared = HotKeyStatus()
    /// While true the global shortcut is unregistered, so recording the current combination does not fire it.
    @Published var isRecording = false {
        didSet { if isRecording != oldValue { NotificationCenter.default.post(name: .projectCanvasHotKeyChanged, object: nil) } }
    }
    /// Set when macOS refused the shortcut, typically because another app already owns it.
    @Published var registrationFailed = false
    /// The current shortcut, for labels that show it.
    @Published var shortcut = HotKeyShortcut.load()
}
