import Foundation
import Observation

/// The app's sense of time and of which day is on screen.
///
/// Everything reads the day from `now` rather than from the system clock, so a
/// test can move the day without waiting out a midnight and a stale reading
/// never marks two days as today at once.
@MainActor
@Observable
public final class Clock {
    public var now: Date = .now
    public var selectedDay: Date = .now {
        didSet { onDayChange?() }
    }
    /// The day the window was last brought to the front. Internal so a test
    /// can put it in the past instead of waiting for midnight.
    var lastOpenedAt: Date = .now
    /// Called when the day on screen changes, so a selection made on the old
    /// day can be let go.
    public var onDayChange: (() -> Void)?

    private let weekCalendar = WeekCalendar()

    public init() {}

    public var weekDays: [Date] { weekCalendar.week(containing: selectedDay) }

    /// The week today falls in, whichever day the window is looking at.
    var currentWeek: [Date] { weekCalendar.week(containing: .now) }

    func days(from first: Day, to last: Day) -> [Day] {
        weekCalendar.days(from: first, to: last)
    }

    /// Whether the day on screen is the one today falls in, so a control can
    /// offer a way back only when there is somewhere to come back from. A day
    /// earlier in this same week counts as somewhere else, so the way back is
    /// on offer there too.
    public var isViewingToday: Bool { isToday(selectedDay) }

    /// Whether `day` is the one the clock is in.
    public func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: now)
    }

    public func goToToday() {
        selectedDay = now
    }

    /// Moves the clock on and rolls the view over if the day changed under it.
    /// Returns how long the step was, which the away watch reads as the gap it
    /// has to account for. Only follows the clock past midnight for someone
    /// still looking at what was today; anyone browsing another day stays.
    func tick() -> TimeInterval {
        let previous = now
        now = .now
        if Calendar.current.isDate(selectedDay, inSameDayAs: previous),
           !Calendar.current.isDate(now, inSameDayAs: previous) {
            goToToday()
        }
        return now.timeIntervalSince(previous)
    }

    /// Call when the window comes to the front. The first open of a calendar
    /// day lands on today, wherever the app was left the day before; later
    /// opens the same day leave the chosen day alone.
    public func windowDidOpen() {
        now = .now
        if !Calendar.current.isDate(lastOpenedAt, inSameDayAs: now) {
            goToToday()
        }
        lastOpenedAt = now
    }
}
