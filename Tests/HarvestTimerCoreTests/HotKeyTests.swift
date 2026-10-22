import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Hot key")
@MainActor
func runHotKeyTests() async {
    test("prints modifiers in menu order") {
        let key = HotKey(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | shiftKey | controlKey),
            key: "K"
        )
        expect(key.display == "⌃⇧⌘K", key.display)
    }

    test("defaults to ⌃⌥H, clear of Pigeonhole's ⌥⌘P") {
        expect(HotKey.standard.display == "⌃⌥H", HotKey.standard.display)
    }

    test("a bare key or shift alone is no shortcut") {
        let bare = HotKey(keyCode: UInt16(kVK_ANSI_H), flags: [], characters: "h")
        let shifted = HotKey(keyCode: UInt16(kVK_ANSI_H), flags: [.shift], characters: "h")
        expect(bare == nil, "a bare letter would swallow typing")
        expect(shifted == nil, "shift alone is still typing")
    }

    test("a recorded press keeps its modifiers and names the key") {
        let key = HotKey(keyCode: UInt16(kVK_Space), flags: [.control, .option], characters: " ")
        expect(key?.display == "⌃⌥Space", key?.display ?? "nil")
    }

    await test("the shortcut comes back on the next launch") {
        try await withTemporaryDirectory { directory in
            let suite = "HarvestTimerTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let first = AppState(client: FakeHarvest(), storageDirectory: directory, defaults: defaults)
            expect(first.hotKey == .standard, "starts on the default")
            let picked = HotKey(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), key: "T")
            first.hotKey = picked

            let second = AppState(client: FakeHarvest(), storageDirectory: directory, defaults: defaults)
            expect(second.hotKey == picked, "got \(second.hotKey.display)")
        }
    }
}
