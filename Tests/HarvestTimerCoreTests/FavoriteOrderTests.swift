import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Favorite order")
func runFavoriteOrderTests() {
    let pitch = FavoriteOrder.pitch

    test("a short drag lands where it started") {
        expect(
            FavoriteOrder.destination(from: 1, translation: pitch / 2 - 1, count: 4) == 1,
            "under half a pitch should not move the chip"
        )
        expect(
            FavoriteOrder.destination(from: 1, translation: 0, count: 4) == 1,
            "no travel should not move the chip"
        )
    }

    test("half a pitch of travel moves one place") {
        expect(
            FavoriteOrder.destination(from: 1, translation: pitch / 2 + 1, count: 4) == 2,
            "just over half a pitch right should move one right"
        )
        expect(
            FavoriteOrder.destination(from: 1, translation: -(pitch / 2 + 1), count: 4) == 0,
            "just over half a pitch left should move one left"
        )
        expect(
            FavoriteOrder.destination(from: 0, translation: pitch * 2, count: 4) == 2,
            "two pitches right should move two places"
        )
    }

    test("a drag past the row is pinned to the row") {
        expect(
            FavoriteOrder.destination(from: 1, translation: 1000, count: 3) == 2,
            "dragging off the right should stop at the last index"
        )
        expect(
            FavoriteOrder.destination(from: 1, translation: -1000, count: 3) == 0,
            "dragging off the left should stop at the first index"
        )
        expect(
            FavoriteOrder.destination(from: 0, translation: 100, count: 0) == 0,
            "an empty row has nowhere to land"
        )
    }

    test("chips between the chip and its landing place slide aside") {
        expect(
            FavoriteOrder.displacement(of: 1, draggedFrom: 0, to: 2) == -pitch,
            "a chip passed on the way right should slide left"
        )
        expect(
            FavoriteOrder.displacement(of: 2, draggedFrom: 0, to: 2) == -pitch,
            "the chip at the landing place should slide left too"
        )
        expect(
            FavoriteOrder.displacement(of: 3, draggedFrom: 0, to: 2) == 0,
            "a chip beyond the landing place should not move"
        )

        expect(
            FavoriteOrder.displacement(of: 2, draggedFrom: 3, to: 1) == pitch,
            "a chip passed on the way left should slide right"
        )
        expect(
            FavoriteOrder.displacement(of: 1, draggedFrom: 3, to: 1) == pitch,
            "the chip at the landing place should slide right too"
        )
        expect(
            FavoriteOrder.displacement(of: 0, draggedFrom: 3, to: 1) == 0,
            "a chip before the landing place should not move"
        )
        expect(
            FavoriteOrder.displacement(of: 1, draggedFrom: 1, to: 1) == 0,
            "a chip that goes nowhere displaces nothing"
        )
    }

    test("the dragged chip is held inside the row") {
        expect(
            FavoriteOrder.heldTranslation(-1000, from: 0, count: 3) == 0,
            "the first chip cannot be dragged left of the row"
        )
        expect(
            FavoriteOrder.heldTranslation(1000, from: 2, count: 3) == 0,
            "the last chip cannot be dragged right of the row"
        )
        expect(
            FavoriteOrder.heldTranslation(1000, from: 0, count: 3) == pitch * 2,
            "the first chip can reach the last place and no further"
        )
        expect(
            FavoriteOrder.heldTranslation(5, from: 1, count: 3) == 5,
            "a drag inside the row is passed through untouched"
        )
    }

    test("moving an element rewrites the array around it") {
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: 0, to: 2) == ["B", "C", "A"],
            "moving the first to last should shuffle the rest down"
        )
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: 2, to: 0) == ["C", "A", "B"],
            "moving the last to first should shuffle the rest up"
        )
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: 0, to: 1) == ["B", "A", "C"],
            "a one-place move should swap neighbours"
        )
    }

    test("a move that changes nothing leaves the array alone") {
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: 1, to: 1) == ["A", "B", "C"],
            "moving a chip onto itself should do nothing"
        )
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: 0, to: 9) == ["A", "B", "C"],
            "a landing index off the end should do nothing"
        )
        expect(
            FavoriteOrder.moving(["A", "B", "C"], from: -1, to: 0) == ["A", "B", "C"],
            "a starting index off the front should do nothing"
        )
        expect(
            FavoriteOrder.moving(["A"], from: 0, to: 0) == ["A"],
            "a single chip has nowhere to go"
        )
        expect(
            FavoriteOrder.moving([String](), from: 0, to: 0).isEmpty,
            "an empty row has nothing to move"
        )
    }
}

@Test("Favorite label")
func runFavoriteLabelTests() {
    func favorite(project: String, nickname: String? = nil) -> Favorite {
        Favorite(
            projectId: 1,
            taskId: 2,
            clientName: "Client",
            projectName: project,
            taskName: "Development",
            nickname: nickname
        )
    }

    test("a nickname wins over the project name") {
        expect(
            favorite(project: "Acme – Website", nickname: "web").chipLabel == "WEB",
            "the nickname should be what the chip reads"
        )
    }

    test("a nickname is uppercased and cut to the chip width") {
        expect(
            favorite(project: "Acme", nickname: "Admin!!").chipLabel == "ADMIN!",
            "a nickname should be uppercased and cut to six"
        )
    }

    test("an empty or blank nickname falls back to the project name") {
        expect(
            favorite(project: "Acme – Website", nickname: "").chipLabel == "WEBSIT",
            "an empty nickname is no nickname"
        )
        expect(
            favorite(project: "Acme – Website", nickname: "   ").chipLabel == "WEBSIT",
            "whitespace is no nickname either"
        )
    }

    test("the derived name drops the client prefix") {
        expect(
            favorite(project: "Acme – Website").chipLabel == "WEBSIT",
            "an en dash should separate client from project"
        )
        expect(
            favorite(project: "Acme — Portal").chipLabel == "PORTAL",
            "an em dash should separate too"
        )
        expect(
            favorite(project: "Acme - Portal").chipLabel == "PORTAL",
            "a spaced hyphen should separate too"
        )
    }

    test("a name with nothing to strip is used as it stands") {
        expect(
            favorite(project: "Maintenance").chipLabel == "MAINTE",
            "a plain name should just be cut to six"
        )
        expect(
            favorite(project: "Acme-Portal").chipLabel == "ACME-P",
            "a hyphen without spaces is part of the name, not a separator"
        )
        expect(
            favorite(project: "Acme – ").chipLabel == "ACME –",
            "an empty tail should leave the whole name alone"
        )
    }

    test("no label is ever longer than the chip") {
        let names = ["Maintenance", "Acme – Website Redesign", "A", "Acme-Portal"]
        for name in names {
            expect(
                favorite(project: name).chipLabel.count <= Favorite.maxLabelLength,
                "“\(name)” gave a label longer than the chip"
            )
        }
    }
}
