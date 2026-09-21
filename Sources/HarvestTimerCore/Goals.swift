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
    /// Whether the day's goal comes from Almanac's suggested pace instead of
    /// the hand-set hours below. Those hours are kept either way — as the
    /// base to adjust when only `almanacTimeOffEnabled` is on, and as the
    /// fallback whenever neither is, or Almanac has nothing to say yet.
    public var almanacPaceEnabled: Bool
    /// Whether a day's number gets scaled down for time off Almanac knows
    /// about, independent of whether the number itself came from Almanac's
    /// pace or the hand-set hours — someone may want their own pace with
    /// Almanac only stepping in for a half day or a day off.
    public var almanacTimeOffEnabled: Bool

    public init(
        isEnabled: Bool = false,
        days: [Weekday: DayGoal] = [:],
        breakSkippedOn: Day? = nil,
        almanacPaceEnabled: Bool = false,
        almanacTimeOffEnabled: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.days = days
        self.breakSkippedOn = breakSkippedOn
        self.almanacPaceEnabled = almanacPaceEnabled
        self.almanacTimeOffEnabled = almanacTimeOffEnabled
    }

    /// Hand-written because the synthesized one throws on a file saved before
    /// a key existed, and a goals file is worth keeping across a version.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        days = try container.decodeIfPresent([Weekday: DayGoal].self, forKey: .days) ?? [:]
        breakSkippedOn = try container.decodeIfPresent(Day.self, forKey: .breakSkippedOn)
        // `almanacEnabled` is what the combined switch used to be called,
        // before pace and time off split into their own toggles — read it
        // from a key of its own, so a file saved under the old name keeps
        // doing what it did rather than losing the setting outright.
        let legacyContainer = try? decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyAlmanacEnabled = try legacyContainer?.decodeIfPresent(Bool.self, forKey: .almanacEnabled) ?? false
        almanacPaceEnabled = try container.decodeIfPresent(Bool.self, forKey: .almanacPaceEnabled) ?? legacyAlmanacEnabled
        almanacTimeOffEnabled = try container.decodeIfPresent(Bool.self, forKey: .almanacTimeOffEnabled) ?? legacyAlmanacEnabled
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case almanacEnabled
    }

    /// Nothing while the feature is off, so every reader of a goal is gated by
    /// the switch without knowing about it.
    public func goal(for weekday: Weekday) -> DayGoal? {
        guard isEnabled, let goal = days[weekday], goal.isSet else { return nil }
        return goal
    }
}
