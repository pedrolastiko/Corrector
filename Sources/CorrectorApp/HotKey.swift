import AppKit
import Carbon.HIToolbox
import CorrectorAppCore

/// A system-wide keyboard shortcut.
///
/// Registered through the Carbon hot-key API rather than a `CGEventTap`,
/// deliberately: an event tap would see **every** keystroke in every
/// application and needs Accessibility permission to do it. A registered hot
/// key tells the system "wake me for exactly this combination" and sees
/// nothing else. For a feature that only ever acts on demand, that is the
/// right amount of reach — and it needs no permission at all.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1

    private let id: UInt32

    /// - Parameters:
    ///   - keyCode: a virtual key code, e.g. `kVK_ANSI_C`.
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | shiftKey`.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        self.id = Self.nextID
        Self.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            HotKey.registry[hotKeyID.id]?.action()
            return noErr
        }, 1, &eventType, nil, &handler)
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x434F5252), id: id)  // 'CORR'
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
        guard registered == noErr, ref != nil else { return nil }
        Self.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        Self.registry[id] = nil
    }
}
