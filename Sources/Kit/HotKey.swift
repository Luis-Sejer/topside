import Carbon.HIToolbox

/// Global shortcut via Carbon, the only public API that works without Accessibility permission (from Snicker).
/// Nil when another app already holds the shortcut.
public final class HotKey {
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void
    private let id: UInt32

    /// `keyCode` is a `kVK_` constant; `modifiers` combines Carbon's `cmdKey`, `optionKey`, `controlKey` and `shiftKey`.
    public init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Every registration gets every hotkey event, so each passes on the ones that aren't its own.
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.action()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        let hotKeyID = EventHotKeyID(signature: OSType(0x5450_5344), id: id) // "TPSD"
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
