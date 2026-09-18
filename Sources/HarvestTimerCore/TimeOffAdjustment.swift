import Foundation

/// How a day's Almanac pace scales down for time off landing on it.
///
/// Plain numbers in, plain numbers out — no network or disk, so this can be
/// tested against a fixed list of constraints without any of Almanac in the
/// room, the same split `GoalProgress` keeps from `AppState`.
public enum TimeOffAdjustment {
    /// What `basePace` becomes for `day`, or nil on a weekend — Almanac's own
    /// pace calculator (`WorkHourCalculator`) is Mon–Fri only, so there is no
    /// pace to adjust there in the first place.
    ///
    /// Company holidays count as time off too: `company_wide` constraints
    /// come back from Almanac already merged into a person's own.
    public static func hours(
        forDay day: Day,
        basePace: Double,
        constraints: [AlmanacConstraint]
    ) -> Double? {
        guard let date = day.date, Weekday.workdays.contains(Weekday(date)) else { return nil }

        let covering = constraints.filter { !$0.billableOnly && $0.covers(day) }
        guard !covering.isEmpty else { return basePace }

        // The biggest bite out of the day wins rather than the sum of them —
        // two constraints on the same day can't put you further out than
        // entirely unavailable.
        let reduction = covering.map(fraction(off:)).max() ?? 0
        return max(0, basePace * (1 - reduction))
    }

    /// How much of the workday one constraint takes, 0 through 1. A whole
    /// day or a multi-day stretch takes all of it; a partial day is
    /// pro-rated against an assumed 8-hour day, mirroring Almanac's own
    /// `Constraint#hours_within`.
    /// Internal, not private, so `AppState` can name the same weight when
    /// picking which constraint explains a scaled day.
    static func fraction(off constraint: AlmanacConstraint) -> Double {
        guard constraint.isPartialDay,
              let start = constraint.startTime,
              let end = constraint.endTime else { return 1 }
        return min(1, max(0, (end.hours - start.hours) / 8))
    }
}
