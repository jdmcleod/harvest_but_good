import Carbon.HIToolbox
import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Window keys")
@MainActor
func runWindowKeyTests() async {
    test("a fresh install has only Settings and the shortcut list") {
        expect(Set(WindowCommand.defaults.keys) == [.settings, .shortcuts], "got \(WindowCommand.defaults.keys)")
        expect(WindowCommand.defaults[.shortcuts]?.display == "?", "? needs no ⇧ beside it")
    }

    test("no two suggestions share a press") {
        let suggested = WindowCommand.allCases.map(\.suggested)
        for (index, key) in suggested.enumerated() {
            let clash = suggested[(index + 1)...].first(where: key.matches)
            expect(clash == nil, "\(key.display) is suggested twice")
        }
    }

    test("no suggestion takes a digit, which favorites start with") {
        for command in WindowCommand.allCases {
            let key = command.suggested
            expect(!(key.isBare && FavoriteShortcuts.placeKeys.contains(key.key)), "\(command) suggests \(key.display)")
        }
    }

    await test("a letter a favorite holds is not suggested") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            var favorite = Favorite(
                projectId: 1, taskId: 100, clientName: "Acme", projectName: "Acme - Web", taskName: "Development"
            )
            favorite.shortcut = "E"
            state.favorites = [favorite]
            state.useSuggestedBindings()
            expect(state.keyBindings[.editHours] == nil, "E starts the favorite")
            expect(state.keyBindings[.moveTime] == WindowCommand.moveTime.suggested, "M is free")
        }
    }

    test("no suggestion is a key the app keeps") {
        for command in WindowCommand.allCases {
            let key = command.suggested
            expect(!WindowCommand.isReserved(key), "\(command) suggests \(key.display)")
        }
    }

    await test("suggestions fill only the commands without a shortcut") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            let mine = HotKey.window(kVK_Space, "Space", command: true)
            state.setBinding(mine, for: .notes)
            state.setBinding(.window(kVK_Space, "Space"), for: .sync)
            state.useSuggestedBindings()
            expect(state.keyBindings[.notes] == mine, "kept the user's own")
            expect(state.keyBindings[.sync]?.display == "Space", "kept the user's own")
            expect(state.keyBindings[.toggleTimer] == nil, "Space was taken, so it's left unset")
            expect(state.keyBindings[.startTimer] == WindowCommand.startTimer.suggested, "filled the rest")
            expect(state.keyBindings[.shortcuts] == WindowCommand.defaults[.shortcuts], "left ? alone")
        }
    }

    await test("a press given to one command is taken off another") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            let key = HotKey.window(kVK_ANSI_Slash, "?", shift: true)
            state.setBinding(key, for: .notes)
            expect(state.keyBindings[.notes] == key, "given to notes")
            expect(state.keyBindings[.shortcuts] == nil, "taken off the shortcut list")
            expect(state.command(for: key) == .notes, "the press runs notes")
        }
    }

    await test("clearing leaves only Settings and the shortcut list") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.useSuggestedBindings()
            state.setBinding(nil, for: .shortcuts)
            state.clearBindings()
            expect(state.keyBindings == WindowCommand.defaults, "got \(state.keyBindings.count) bindings")
        }
    }

    await test("shortcuts come back on the next launch") {
        try await withTemporaryDirectory { directory in
            let suite = "HarvestTimerTests.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }

            let first = AppState(client: FakeHarvest(), storageDirectory: directory, defaults: defaults)
            first.setBinding(nil, for: .settings)
            first.useSuggestedBindings()
            let second = AppState(client: FakeHarvest(), storageDirectory: directory, defaults: defaults)
            expect(second.keyBindings == first.keyBindings, "got \(second.keyBindings.count) back")
        }
    }

    test("a hotkey splits into one keycap per modifier") {
        expect(HotKey.standard.displayParts == ["⌃", "⌥", "H"], "got \(HotKey.standard.displayParts)")
        let back = HotKey.window(kVK_LeftArrow, "←", shift: true)
        expect(back.displayParts == ["⇧", "←"], "got \(back.displayParts)")
    }
}
