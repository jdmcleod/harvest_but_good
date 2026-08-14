import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Arrow keys walking a list")
func runListCursorTests() {
    let items = [10, 20, 30]

    test("down moves to the next item") {
        expect(ListCursor.moved(from: 10, by: 1, in: items) == 20, "second item")
        expect(ListCursor.moved(from: 20, by: 1, in: items) == 30, "third item")
    }

    test("up moves to the previous item") {
        expect(ListCursor.moved(from: 30, by: -1, in: items) == 20, "second item")
    }

    test("the ends hold") {
        expect(ListCursor.moved(from: 30, by: 1, in: items) == 30, "past the bottom")
        expect(ListCursor.moved(from: 10, by: -1, in: items) == 10, "past the top")
    }

    test("nothing picked yet takes the end the key points away from") {
        expect(ListCursor.moved(from: nil, by: 1, in: items) == 10, "down takes the first")
        expect(ListCursor.moved(from: nil, by: -1, in: items) == 30, "up takes the last")
    }

    test("a pick that has left the list starts over") {
        expect(ListCursor.moved(from: 99, by: 1, in: items) == 10, "first item")
    }

    test("an empty list has nowhere to go") {
        expect(ListCursor.moved(from: 10, by: 1, in: [Int]()) == nil, "no selection")
    }
}
