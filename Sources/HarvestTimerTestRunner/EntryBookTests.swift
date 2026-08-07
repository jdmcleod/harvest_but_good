import Foundation
import HarvestTimerCore

func runEntryBookTests() {
    let monday = day("2026-08-03")
    let tuesday = day("2026-08-04")

    test("a day's entries come back in id order, whatever order they went in") {
        let book = EntryBook([
            entry(id: 3, day: monday, hours: 1, project: 10, task: 100),
            entry(id: 1, day: monday, hours: 2, project: 11, task: 110),
            entry(id: 2, day: tuesday, hours: 3, project: 12, task: 120),
        ])
        expect(book.entries(on: monday).map(\.id) == [1, 3], "Monday should read 1 then 3")
        expect(book.entries(on: tuesday).map(\.id) == [2], "Tuesday holds only its own")
        expect(book.entries(on: day("2026-08-05")).isEmpty, "an untouched day is empty")
        expect(book.all.map(\.id) == [1, 3, 2], "all reads day by day, in id order within each")
    }

    test("an entry is found by id wherever it sits") {
        let book = EntryBook([
            entry(id: 1, day: monday, hours: 1, project: 10, task: 100),
            entry(id: 2, day: tuesday, hours: 2, project: 11, task: 110),
        ])
        expect(book.entry(withId: 2)?.hours == 2, "should reach across days")
        expect(book.entry(withId: 9) == nil, "an id that is not there reads as nothing")
    }

    test("only one entry runs at a time") {
        var book = EntryBook([
            entry(id: 1, day: monday, hours: 1, project: 10, task: 100, running: true),
            entry(id: 2, day: monday, hours: 2, project: 11, task: 110),
        ])
        expect(book.running?.id == 1, "entry 1 starts out running")

        book.apply(entry(id: 2, day: monday, hours: 2, project: 11, task: 110, running: true))
        expect(book.running?.id == 2, "starting 2 should make it the running one")
        expect(book.entry(withId: 1)?.isRunning == false, "and should stop 1")
    }

    test("a running entry stops the one running on another day") {
        var book = EntryBook([
            entry(id: 1, day: monday, hours: 1, project: 10, task: 100, running: true),
        ])
        book.apply(entry(id: 2, day: tuesday, hours: 0, project: 11, task: 110, running: true))
        expect(book.entry(withId: 1)?.isRunning == false, "yesterday's timer should stop too")
        expect(book.running?.id == 2, "and today's should be the live one")
    }

    test("applying an entry that is not filed yet adds it") {
        var book = EntryBook()
        book.apply(entry(id: 1, day: monday, hours: 0.5, project: 10, task: 100))
        expect(book.entries(on: monday).count == 1, "it should be filed on its own day")

        book.apply(entry(id: 1, day: monday, hours: 1.5, project: 10, task: 100))
        expect(book.entries(on: monday).count == 1, "applying it again should replace, not double")
        expect(book.entry(withId: 1)?.hours == 1.5, "with the newer hours")
    }

    test("the current version is the one on file, not the caller's copy") {
        let stale = entry(id: 1, day: monday, hours: 1, project: 10, task: 100)
        var book = EntryBook([stale])
        book.apply(entry(id: 1, day: monday, hours: 4, project: 10, task: 100))
        expect(book.currentVersion(of: stale).hours == 4, "should read the filed hours")

        let unknown = entry(id: 7, day: monday, hours: 1, project: 10, task: 100)
        expect(book.currentVersion(of: unknown).id == 7, "an unfiled entry falls back to itself")
    }

    test("removing an entry leaves its day's others alone") {
        var book = EntryBook([
            entry(id: 1, day: monday, hours: 1, project: 10, task: 100),
            entry(id: 2, day: monday, hours: 2, project: 11, task: 110),
        ])
        book.remove(book.entry(withId: 1)!)
        expect(book.entries(on: monday).map(\.id) == [2], "only 1 should go")
    }

    test("a sync replaces the days it covers and leaves the rest") {
        var book = EntryBook([
            entry(id: 1, day: monday, hours: 1, project: 10, task: 100),
            entry(id: 2, day: tuesday, hours: 2, project: 11, task: 110),
        ])
        // Harvest reports Monday only, and entry 1 is gone from it.
        book.replace([monday], with: [entry(id: 3, day: monday, hours: 5, project: 12, task: 120)])
        expect(book.entries(on: monday).map(\.id) == [3], "Monday should read as Harvest has it")
        expect(book.entry(withId: 1) == nil, "an entry deleted in Harvest should go")
        expect(book.entry(withId: 2)?.hours == 2, "Tuesday was not in the range, so it stays")
    }

    test("a day in the range with nothing in it empties") {
        var book = EntryBook([entry(id: 1, day: monday, hours: 1, project: 10, task: 100)])
        book.replace([monday, tuesday], with: [])
        expect(book.all.isEmpty, "both days should now be empty")
    }

    test("removeAll clears the book") {
        var book = EntryBook([entry(id: 1, day: monday, hours: 1, project: 10, task: 100)])
        book.removeAll()
        expect(book.all.isEmpty, "signing out should leave nothing behind")
        expect(book.running == nil, "and nothing running")
    }
}
