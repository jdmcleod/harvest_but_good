import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Favorite shortcuts")
@MainActor
func runFavoriteShortcutTests() async {
    func favorites(_ count: Int) -> [Favorite] {
        (1...count).map { n in
            Favorite(
                projectId: Int64(n),
                taskId: 100,
                clientName: "Client",
                projectName: "Project \(n)",
                taskName: "Development"
            )
        }
    }

    test("the first ten go 1 to 9 then 0, and the rest have none") {
        let list = favorites(11)
        let keys = list.map { FavoriteShortcuts.key(for: $0, in: list) }
        expect(keys == ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", nil], "got \(keys)")
    }

    test("a key of its own replaces the one its place gave it") {
        var list = favorites(3)
        list[1].shortcut = "A"
        expect(FavoriteShortcuts.key(for: list[1], in: list) == "A", "the custom key")
        expect(FavoriteShortcuts.favorite(forKey: "A", in: list)?.id == list[1].id, "A finds it")
        expect(FavoriteShortcuts.favorite(forKey: "2", in: list) == nil, "2 is left free")
    }

    test("a custom key takes the place key from whoever would have had it") {
        var list = favorites(3)
        list[0].shortcut = "3"
        expect(FavoriteShortcuts.key(for: list[2], in: list) == nil, "the third gives up 3")
        expect(FavoriteShortcuts.favorite(forKey: "3", in: list)?.id == list[0].id, "3 starts the first")
    }

    test("keys are matched without regard to case") {
        var list = favorites(1)
        list[0].shortcut = "B"
        expect(FavoriteShortcuts.favorite(forKey: "b", in: list)?.id == list[0].id, "lower case b")
    }

    await test("giving a favorite a key another holds moves it over") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            var list = favorites(2)
            list.forEach(state.addFavorite)
            list[0].shortcut = "Q"
            state.updateFavorite(list[0])
            list[1].shortcut = "Q"
            state.updateFavorite(list[1])

            expect(state.favorites[0].shortcut == nil, "the first goes back to its place")
            expect(state.favorites[1].shortcut == "Q", "the second holds Q")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.favorites.map(\.shortcut) == [nil, "Q"], "and it is saved")
        }
    }

    test("favorites saved before shortcuts still load") {
        let json = #"[{"projectId":1,"taskId":2,"clientName":"C","projectName":"P","taskName":"T"}]"#
        let decoded = try JSONDecoder().decode([Favorite].self, from: Data(json.utf8))
        expect(decoded.first?.shortcut == nil, "no shortcut means its place")
    }
}
