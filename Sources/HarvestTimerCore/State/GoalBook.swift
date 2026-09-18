import Foundation
import Observation

/// The daily goals: how long each weekday is meant to be, whether the feature
/// is on at all, and which day's break has been waved off. Owns its file, so a
/// change is saved as it is made.
@MainActor
@Observable
public final class GoalBook {
    private(set) var settings = GoalSettings()
    private let store: GoalsStore

    public init(store: GoalsStore) {
        self.store = store
        settings = store.load()
    }

    public var isEnabled: Bool { settings.isEnabled }

    /// The goal for the weekday `day` falls on, or nil for a day left blank.
    public func goal(forDay day: Date) -> DayGoal? {
        settings.goal(for: Weekday(day))
    }

    /// The goal stored against a weekday, whether or not it is set. For the
    /// settings screen, which edits days the feature switch may be hiding.
    public func storedGoal(for weekday: Weekday) -> DayGoal? {
        settings.days[weekday]
    }

    /// Whether the break has been waved off for `day`. Yesterday's marker
    /// simply stops matching, so nothing has to clear it.
    public func isBreakSkipped(forDay day: Date) -> Bool {
        settings.breakSkippedOn == Day(day)
    }

    /// Turns the whole goals feature on or off. The days keep their goals
    /// either way, so switching back on picks up where it left off.
    public func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        store.save(settings)
    }

    /// Sets the goal for a weekday. Hours of nothing leaves the day unset
    /// rather than storing a goal of zero.
    public func setGoal(hours: Double, breakHours: Double, for weekday: Weekday) {
        if hours > 0 {
            settings.days[weekday] = DayGoal(hours: hours, breakHours: max(0, breakHours))
        } else {
            settings.days.removeValue(forKey: weekday)
        }
        store.save(settings)
    }

    /// Waves a day's break off, or puts it back.
    public func toggleBreakSkip(forDay day: Date) {
        settings.breakSkippedOn = isBreakSkipped(forDay: day) ? nil : Day(day)
        store.save(settings)
    }

    /// How `day` stands against its goal, or nil when it has none. The hours
    /// come from the caller: what was worked is the entries' business and what
    /// break was taken is the timeline's.
    public func progress(forDay day: Date, worked: Double, breakTaken: Double) -> GoalProgress? {
        guard let goal = goal(forDay: day) else { return nil }
        return GoalProgress(
            goalHours: goal.hours,
            workedHours: worked,
            breakAllowanceHours: goal.breakHours,
            breakTakenHours: breakTaken,
            breakSkipped: isBreakSkipped(forDay: day)
        )
    }
}
