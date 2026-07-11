import AppKit
import Carbon.HIToolbox

/// Global hotkey via the Carbon RegisterEventHotKey API.
/// Works without accessibility permissions, unlike NSEvent global monitors.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let handler: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            hotKey.handler()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434D_4443), id: 1) // "CMDC"
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
