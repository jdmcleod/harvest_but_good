import AppKit
import Carbon.HIToolbox

/// A global shortcut, stored as Carbon key code and modifier bits because
/// that's what `RegisterEventHotKey` takes. Carbon hot keys need no
/// Accessibility permission, unlike an event tap.
public struct HotKey: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: UInt32
    public let key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// ⌃⌥ rather than ⌥⌘: ⌥⌘H is Hide Others in every app, and ⌥⌘P is
    /// Pigeonhole's.
    public static let standard = HotKey(
        keyCode: UInt32(kVK_ANSI_H),
        modifiers: UInt32(controlKey | optionKey),
        key: "H"
    )

    /// Brings the window up with the command palette already open.
    public static let openToPalette = HotKey(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(controlKey | optionKey),
        key: "K"
    )

    /// Opens the palette while the window is in front. Never registered with
    /// Carbon, so it costs no other app its ⌘K.
    public static let palette = HotKey(
        keyCode: UInt32(kVK_ANSI_K),
        modifiers: UInt32(cmdKey),
        key: "K"
    )

    /// In the order macOS menus print them: ⌃⌥⇧⌘.
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// One keycap per modifier, then the key, as the palette draws them.
    public var displayParts: [String] {
        display.dropLast(key.count).map(String.init) + [key]
    }

    /// Compared by key code and modifiers alone: the name a press yields can
    /// differ from the stored one by case or keyboard layout.
    public func matches(_ event: NSEvent) -> Bool {
        guard let pressed = HotKey(event: event) else { return false }
        return pressed.keyCode == keyCode && pressed.modifiers == modifiers
    }

    /// Nil unless the press holds ⌘, ⌥ or ⌃. A bare letter as a global
    /// shortcut would swallow that letter in every other app.
    public init?(event: NSEvent) {
        self.init(
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            characters: event.charactersIgnoringModifiers
        )
    }

    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        guard !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let key = Self.keyNames[Int(keyCode)] ?? characters?.uppercased() ?? ""
        guard !key.isEmpty else { return nil }
        self.init(keyCode: UInt32(keyCode), modifiers: modifiers, key: key)
    }

    static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

/// The global shortcuts the app holds, each under its own Carbon id.
public enum HotKeySlot: UInt32, CaseIterable, Sendable {
    case showHide = 1
    case openToPalette = 2
}

@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public var onPress: ((HotKeySlot) -> Void)?
    private var keys: [HotKeySlot: HotKey] = [:]
    private var refs: [HotKeySlot: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    /// Replaces whatever the slot held. False when another app already owns
    /// the combination, and the slot keeps the key it had.
    @discardableResult
    public func register(_ key: HotKey, for slot: HotKeySlot) -> Bool {
        unregister(slot)
        installHandler()
        guard let ref = Self.carbonRegister(key, slot: slot) else {
            if let previous = keys[slot] { refs[slot] = Self.carbonRegister(previous, slot: slot) }
            return false
        }
        refs[slot] = ref
        keys[slot] = key
        return true
    }

    /// Lets the settings recorder hear a shortcut the app already holds
    /// instead of the window toggling while you're trying to type it.
    public func suspend() {
        for slot in HotKeySlot.allCases { unregister(slot) }
    }

    public func resume() {
        for (slot, key) in keys where refs[slot] == nil {
            refs[slot] = Self.carbonRegister(key, slot: slot)
        }
    }

    private func unregister(_ slot: HotKeySlot) {
        if let ref = refs.removeValue(forKey: slot) { UnregisterEventHotKey(ref) }
    }

    private static func carbonRegister(_ key: HotKey, slot: HotKeySlot) -> EventHotKeyRef? {
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4842_4744, id: slot.rawValue) // "HBGD"
        let status = RegisterEventHotKey(
            key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        return status == noErr ? ref : nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id
            )
            guard let slot = HotKeySlot(rawValue: id.id) else { return noErr }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.onPress?(slot) }
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
