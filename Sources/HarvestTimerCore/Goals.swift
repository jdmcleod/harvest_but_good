import Foundation

/// How long a weekday is meant to be, and how much of a break goes with it.
///
/// The break is not part of the goal: eight hours means eight hours tracked,
/// and a half hour break only moves the time you finish at.
public struct DayGoal: Codable, Equatable, Sendable {
    public var hours: Double
    public var breakHours: Double

    public init(hours: Double, breakHours: Double = 0) {
        self.hours = hours
        self.breakHours = breakHours
    }

    /// A goal of nothing is no goal at all, so a day left blank in settings
    /// reads the same as a day never configured.
    public var isSet: Bool { hours > 0 }
}

public struct GoalSettings: Codable, Equatable, Sendable {
    /// Off until asked for, so the app says nothing about goals to someone who
    /// does not want them.
    public var isEnabled: Bool
    public var days: [Weekday: DayGoal]
    /// The day whose break was waved off. A `Day` rather than a flag so it
    /// expires on its own at midnight and still holds across a relaunch.
    public var breakSkippedOn: Day?

    public init(
        isEnabled: Bool = false,
        days: [Weekday: DayGoal] = [:],
        breakSkippedOn: Day? = nil
    ) {
        self.isEnabled = isEnabled
        self.days = days
        self.breakSkippedOn = breakSkippedOn
    }

    /// Hand-written because the synthesized one throws on a file saved before
    /// a key existed, and a goals file is worth keeping across a version.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        days = try container.decodeIfPresent([Weekday: DayGoal].self, forKey: .days) ?? [:]
        breakSkippedOn = try container.decodeIfPresent(Day.self, forKey: .breakSkippedOn)
    }

    /// Nothing while the feature is off, so every reader of a goal is gated by
    /// the switch without knowing about it.
    public func goal(for weekday: Weekday) -> DayGoal? {
        guard isEnabled, let goal = days[weekday], goal.isSet else { return nil }
        return goal
    }
}
