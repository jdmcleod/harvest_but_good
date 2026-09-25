import Foundation
import Testing

@testable import HarvestTimerCore

@Test("AlmanacBook")
func runAlmanacBookTests() {
    let today = day("2025-08-06")
    let now = today.date!.addingTimeInterval(12 * 3600)

    test("time off cancelled in Almanac drops out on the next fetch") {
        var book = AlmanacBook()
        book.received(constraints: [constraint(id: 1, start: day("2025-08-20"))], at: now)
        expect(book.constraints.count == 1, "the vacation synced")

        book.received(constraints: [], at: now)

        expect(book.constraints.isEmpty, "the cancelled vacation lingered, got \(book.constraints)")
    }

    test("an edited constraint replaces the cached one") {
        var book = AlmanacBook()
        book.received(constraints: [constraint(id: 1, start: day("2025-08-20"))], at: now)

        book.received(
            constraints: [constraint(id: 1, start: day("2025-08-20"), end: day("2025-08-22"))],
            at: now
        )

        expect(book.constraints.map(\.endDate) == [day("2025-08-22")], "got \(book.constraints)")
    }

    test("a constraint ending today survives Almanac no longer returning it") {
        var book = AlmanacBook()
        let yesterday = now.addingTimeInterval(-24 * 3600)
        book.received(constraints: [constraint(id: 1, start: today)], at: yesterday)

        book.received(constraints: [], at: now)

        expect(book.constraints.map(\.id) == [1], "the half day today was thrown away")
    }

    test("a stretch that started earlier but ends today survives too") {
        var book = AlmanacBook()
        let lastWeek = now.addingTimeInterval(-7 * 24 * 3600)
        book.received(constraints: [constraint(id: 1, start: day("2025-07-30"), end: today)], at: lastWeek)

        book.received(constraints: [], at: now)

        expect(book.constraints.map(\.id) == [1], "the stretch ending today was thrown away")
    }

    test("a constraint that ended yesterday is dropped once Almanac stops returning it") {
        var book = AlmanacBook()
        let twoDaysAgo = now.addingTimeInterval(-2 * 24 * 3600)
        book.received(constraints: [constraint(id: 1, start: day("2025-08-05"))], at: twoDaysAgo)

        book.received(constraints: [], at: now)

        expect(book.constraints.isEmpty, "got \(book.constraints)")
    }
}
