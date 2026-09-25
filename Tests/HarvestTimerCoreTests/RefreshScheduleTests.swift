import Foundation
import Testing

@testable import HarvestTimerCore

/// Records each wait a ticker asks for, then parks so the loop stops there.
private final class Waits: @unchecked Sendable {
    private(set) var recorded: [Duration] = []

    func wait(_ duration: Duration) async {
        recorded.append(duration)
        try? await Task.sleep(for: .seconds(3600))
    }
}

@Test("RefreshSchedule")
@MainActor
func runRefreshScheduleTests() async {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    let schedule = RefreshSchedule(hours: [7, 17], calendar: utc)
    let midnight = utc.startOfDay(for: base)
    func at(_ hour: Double, dayOffset: Int = 0) -> Date {
        midnight.addingTimeInterval(Double(dayOffset) * 24 * 3600 + hour * 3600)
    }

    test("the latest slot is this morning's between 7am and 5pm") {
        expect(schedule.latest(atOrBefore: at(9)) == at(7), "got \(String(describing: schedule.latest(atOrBefore: at(9))))")
        expect(schedule.latest(atOrBefore: at(7)) == at(7), "a slot counts at its own instant")
    }

    test("before 7am the latest slot is yesterday evening's") {
        expect(schedule.latest(atOrBefore: at(6)) == at(17, dayOffset: -1), "got \(String(describing: schedule.latest(atOrBefore: at(6))))")
    }

    test("the next slot after the evening one is tomorrow morning") {
        expect(schedule.next(after: at(18)) == at(7, dayOffset: 1), "got \(String(describing: schedule.next(after: at(18))))")
        expect(schedule.next(after: at(7)) == at(17), "strictly after, so 7am itself points at 5pm")
    }

    test("Almanac is due only once a slot has passed since the last fetch") {
        var book = AlmanacBook()
        expect(book.needsRefresh(force: false, now: at(9), schedule: schedule), "never fetched")

        book.received(constraints: [], at: at(7.5))
        expect(!book.needsRefresh(force: false, now: at(16), schedule: schedule), "fetched since 7am")
        expect(book.needsRefresh(force: true, now: at(16), schedule: schedule), "Sync Now still forces it")
        expect(book.needsRefresh(force: false, now: at(17), schedule: schedule), "5pm is due")

        book.received(constraints: [], at: at(17))
        expect(!book.needsRefresh(force: false, now: at(6, dayOffset: 1), schedule: schedule), "nothing due overnight")
        expect(book.needsRefresh(force: false, now: at(7, dayOffset: 1), schedule: schedule), "due again next morning")
    }

    await test("the ticker waits until the next slot after a finished round") {
        let waits = Waits()
        let nine = at(9)
        var runs = 0
        let ticker = ScheduledTicker(
            schedule: schedule,
            now: { nine },
            sleep: { await waits.wait($0) }
        )
        ticker.start { runs += 1; return true }
        while waits.recorded.isEmpty { await Task.yield() }
        expect(runs == 1, "ran straight away")
        expect(waits.recorded == [.seconds(8 * 3600)], "9am to 5pm, got \(waits.recorded)")
        ticker.stop()
    }

    await test("the ticker retries soon after a round that didn't finish") {
        let waits = Waits()
        let nine = at(9)
        let ticker = ScheduledTicker(
            schedule: schedule,
            retryInterval: .seconds(300),
            now: { nine },
            sleep: { await waits.wait($0) }
        )
        ticker.start { false }
        while waits.recorded.isEmpty { await Task.yield() }
        expect(waits.recorded == [.seconds(300)], "got \(waits.recorded)")
        ticker.stop()
    }
}
