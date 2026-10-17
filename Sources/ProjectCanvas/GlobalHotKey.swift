import Carbon
import Foundation

/// A system hot key uses Carbon registration without an accessibility permission prompt.
@MainActor
final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private let identifier: UInt32
    /// False when macOS rejected the combination, e.g. because another app registered it first.
    private(set) var isRegistered = false

    convenience init(shortcut: HotKeyShortcut, identifier: UInt32 = 1, action: @escaping () -> Void) {
        self.init(keyCode: UInt32(shortcut.keyCode), modifiers: shortcut.carbonModifiers, identifier: identifier, action: action)
    }

    init(keyCode: UInt32, modifiers: UInt32, identifier: UInt32 = 1, action: @escaping () -> Void) {
        self.action = action
        self.identifier = identifier
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            guard status == noErr, identifier.signature == 0x50434E56, identifier.id == owner.identifier else {
                return OSStatus(eventNotHandledErr)
            }
            // Carbon delivers application events on the main event loop.
            MainActor.assumeIsolated { owner.action() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard handlerStatus == noErr else { return }
        let identifier = EventHotKeyID(signature: 0x50434E56, id: identifier)
        let status = RegisterEventHotKey(keyCode, modifiers, identifier, GetApplicationEventTarget(), 0, &hotKey)
        isRegistered = status == noErr
        if status != noErr, let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
