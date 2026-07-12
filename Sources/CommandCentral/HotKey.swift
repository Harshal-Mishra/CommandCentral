import AppKit
import Carbon.HIToolbox

/// Global hotkey via the Carbon RegisterEventHotKey API.
/// Works without accessibility permissions, unlike NSEvent global monitors.
/// Multiple instances can coexist — each checks the fired hotkey's ID and
/// passes the event along when it belongs to a different instance.
final class HotKey {
    private static var nextID: UInt32 = 1

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void
    private let id: UInt32

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler
        self.id = HotKey.nextID
        HotKey.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var fired = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &fired)
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            guard fired.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
            hotKey.handler()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434D_4443), id: id) // "CMDC"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }
}

/// User-selectable palette hotkeys (Settings → General).
struct HotKeyPreset {
    let name: String
    let keyCode: UInt32
    let carbonModifiers: UInt32
    let menuModifiers: NSEvent.ModifierFlags

    static let all: [HotKeyPreset] = [
        HotKeyPreset(name: "⌥ Space",
                     keyCode: UInt32(kVK_Space),
                     carbonModifiers: UInt32(optionKey),
                     menuModifiers: [.option]),
        HotKeyPreset(name: "⌃ Space",
                     keyCode: UInt32(kVK_Space),
                     carbonModifiers: UInt32(controlKey),
                     menuModifiers: [.control]),
        HotKeyPreset(name: "⌥⌘ Space",
                     keyCode: UInt32(kVK_Space),
                     carbonModifiers: UInt32(optionKey | cmdKey),
                     menuModifiers: [.option, .command]),
        HotKeyPreset(name: "⇧⌘ Space",
                     keyCode: UInt32(kVK_Space),
                     carbonModifiers: UInt32(shiftKey | cmdKey),
                     menuModifiers: [.shift, .command]),
    ]

    static var current: HotKeyPreset {
        let index = UserDefaults.standard.integer(forKey: "hotkeyPreset")
        return all[max(0, min(all.count - 1, index))]
    }
}
