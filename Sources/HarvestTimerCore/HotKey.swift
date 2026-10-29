import AppKit
import Carbon.HIToolbox

/// A shortcut, stored as Carbon key code and modifier bits because that's
/// what `RegisterEventHotKey` takes. Carbon hot keys need no Accessibility
/// permission, unlike an event tap. The window's own shortcuts use the same
/// type, and those may be a bare key.
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

    /// In the order macOS menus print them: ⌃⌥⇧⌘.
    public var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0, !shiftIsInKey { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + key
    }

    /// One keycap per modifier, then the key.
    public var displayParts: [String] {
        display.dropLast(key.count).map(String.init) + [key]
    }

    /// ⇧/ is recorded as "?", which already says Shift.
    private var shiftIsInKey: Bool {
        key.count == 1 && !key.contains(where: \.isLetter) && !Self.keyNames.values.contains(key)
    }

    /// Compared by key code and modifiers alone: the name a press yields can
    /// differ from the stored one by case or keyboard layout.
    public func matches(_ event: NSEvent) -> Bool {
        HotKey(event: event, allowingBareKey: true).map(matches) ?? false
    }

    func matches(_ other: HotKey) -> Bool {
        other.keyCode == keyCode && other.modifiers == modifiers
    }

    /// Nil unless the press holds ⌘, ⌥ or ⌃. A bare letter as a global
    /// shortcut would swallow that letter in every other app.
    /// `allowingBareKey` is for the window's own shortcuts, which only hear
    /// keys while it is in front.
    public init?(event: NSEvent, allowingBareKey: Bool = false) {
        self.init(
            keyCode: event.keyCode,
            flags: event.modifierFlags,
            characters: event.charactersIgnoringModifiers,
            allowingBareKey: allowingBareKey
        )
    }

    init?(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?, allowingBareKey: Bool = false) {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        guard allowingBareKey || !flags.isDisjoint(with: [.command, .option, .control]) else { return nil }
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
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_Escape: "esc",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]
}

@MainActor
public final class HotKeyCenter {
    public static let shared = HotKeyCenter()

    public var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerInstalled = false

    /// Replaces whatever was registered. False when another app already owns
    /// the combination.
    @discardableResult
    public func register(_ key: HotKey) -> Bool {
        suspend()
        installHandler()
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x4842_4744, id: 1) // "HBGD"
        let status = RegisterEventHotKey(
            key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &ref
        )
        guard status == noErr else { return false }
        hotKeyRef = ref
        return true
    }

    /// Lets the settings recorder hear the current shortcut instead of the
    /// window toggling while you're trying to type it.
    public func suspend() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() }
            }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}
