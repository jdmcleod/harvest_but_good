import Foundation

/// What the day looked like, read back out of the event log.
///
/// The log is the only account of when timers ran — Harvest keeps a total, not
/// a history — and this is the reading side of it: the blocks a day draws, the
/// entries whose hours no longer match their blocks, and the breaks between.
@MainActor
public struct Timeline {
    private let log: EventLog
    private let clock: Clock
    private let entries: EntryStore

    init(log: EventLog, clock: Clock, entries: EntryStore) {
        self.log = log
        self.clock = clock
        self.entries = entries
    }

    public func blocks(forDay day: Date) -> [TimelineBlock] {
        let events = log.events(forDay: Day(day))
        return TimelineBuilder.blocks(
            from: events,
            now: clock.now,
            running: entries.runningTimers(forDay: day, events: events)
        )
    }

    /// The entries whose hours no longer add up to their blocks, so the day
    /// can stripe them.
    public func modifiedEntryIds(forDay day: Date) -> Set<Int64> {
        TimelineBuilder.modifiedEntryIds(from: log.events(forDay: Day(day)))
    }

    public func startCounts(forDay day: Date) -> [Int64: Int] {
        TimelineBuilder.startCounts(from: log.events(forDay: Day(day)))
    }

    /// How much break the day has already had, taken from the gaps between
    /// tracked blocks.
    ///
    /// A break under way right now is not a gap yet — a gap needs a block on
    /// both sides — so the figure only catches up once the next timer starts.
    public func breakTakenHours(forDay day: Date) -> Double {
        TimelineBuilder.breaks(between: blocks(forDay: day))
            .reduce(0) { $0 + $1.duration } / 3600
    }
}
