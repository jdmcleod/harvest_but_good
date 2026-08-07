import Foundation
import Testing

@testable import HarvestTimerCore

/// A wait that never ends, so a ticker parks after its round instead of
/// spinning while the test looks at what it did.
private func park() async {
    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
}

/// Records what a ticker asked to wait for. The first `rounds` waits return at
/// once, letting the loop go round again; after that the loop parks.
private final class Clock: @unchecked Sendable {
    private(set) var waits: [Duration] = []
    private let rounds: Int

    init(rounds: Int) {
        self.rounds = rounds
    }

    func wait(_ duration: Duration) async {
        waits.append(duration)
        if waits.count >= rounds { await park() }
    }
}

@Test("Ticker")
@MainActor
func runTickerTests() async {
    await test("a ticker runs its work straight away, before the first wait") {
        var runs = 0
        let ticker = Ticker(every: .seconds(30), sleep: { _ in await park() })
        ticker.start { runs += 1 }
        await Task.yield()
        expect(runs == 1, "the first round should not wait for the interval, got \(runs) runs")
        ticker.stop()
    }

    await test("a ticker repeats on its interval") {
        let clock = Clock(rounds: 3)
        var runs = 0
        let ticker = Ticker(every: .seconds(30), sleep: { await clock.wait($0) })
        ticker.start { runs += 1 }
        while runs < 3 { await Task.yield() }
        expect(runs == 3, "three rounds should have run, got \(runs)")
        expect(clock.waits.allSatisfy { $0 == .seconds(30) }, "every wait should be the interval")
        ticker.stop()
    }

    test("stopping a ticker ends the loop") {
        let ticker = Ticker(every: .seconds(30), sleep: { _ in await park() })
        expect(!ticker.isRunning, "a fresh ticker is not running")
        ticker.start {}
        expect(ticker.isRunning, "starting should mark it running")
        ticker.stop()
        expect(!ticker.isRunning, "stopping should mark it stopped")
    }

    await test("starting twice replaces the loop rather than adding one") {
        var first = 0
        var second = 0
        let ticker = Ticker(every: .seconds(30), sleep: { _ in await park() })
        ticker.start { first += 1 }
        await Task.yield()
        ticker.start { second += 1 }
        await Task.yield()
        expect(first == 1, "the first loop should have run once and then stopped, got \(first)")
        expect(second == 1, "the second loop should be the live one, got \(second)")
        ticker.stop()
    }

    test("the sync and AFK loops keep their cadence") {
        expect(AppState.syncInterval == .seconds(30), "sync every 30 seconds")
        expect(AppState.afkInterval == .seconds(10), "check for idleness every 10 seconds")
    }
}
