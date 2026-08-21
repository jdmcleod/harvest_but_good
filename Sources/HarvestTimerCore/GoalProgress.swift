import Foundation

/// How a day stands against its goal: how full it is, how much is left, and
/// what time the day ends if the work carries straight on from here.
///
/// Plain numbers in, plain numbers out — kept apart from the views because
/// none of it is drawing, and apart from `AppState` because none of it needs
/// Harvest or the disk.
public struct GoalProgress: Equatable, Sendable {
    public let goalHours: Double
    public let workedHours: Double
    public let breakAllowanceHours: Double
    public let breakTakenHours: Double
    public let breakSkipped: Bool

    public init(
        goalHours: Double,
        workedHours: Double,
        breakAllowanceHours: Double = 0,
        breakTakenHours: Double = 0,
        breakSkipped: Bool = false
    ) {
        self.goalHours = goalHours
        self.workedHours = workedHours
        self.breakAllowanceHours = breakAllowanceHours
        self.breakTakenHours = breakTakenHours
        self.breakSkipped = breakSkipped
    }

    public var remainingHours: Double { max(0, goalHours - workedHours) }

    /// The part of the break still owed. A break already taken has been paid
    /// out of the day's clock time and no longer pushes the finish time.
    public var remainingBreakHours: Double {
        guard !breakSkipped else { return 0 }
        return max(0, breakAllowanceHours - breakTakenHours)
    }

    /// How full the day is, 0 through 1. A day worked past its goal reads as
    /// full rather than overflowing, since the ring cannot draw more than a
    /// circle.
    public var fraction: Double {
        guard goalHours > 0 else { return 0 }
        return min(1, max(0, workedHours / goalHours))
    }

    public var isMet: Bool { goalHours > 0 && workedHours >= goalHours }

    /// When the day ends if work resumes now and the break still owed is taken
    /// along the way. Nil once the goal is met — there is nothing left to
    /// work until.
    public func finishTime(from now: Date) -> Date? {
        guard goalHours > 0, !isMet else { return nil }
        return now.addingTimeInterval((remainingHours + remainingBreakHours) * 3600)
    }
}
