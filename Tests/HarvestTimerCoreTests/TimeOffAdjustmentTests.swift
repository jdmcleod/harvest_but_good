import Foundation
import Testing

@testable import HarvestTimerCore

@Test("TimeOffAdjustment")
func runTimeOffAdjustmentTests() {
    // A Wednesday and a Saturday, so weekday/weekend cases have fixed dates
    // to work from.
    let wednesday = day("2026-06-17")
    let saturday = day("2026-06-20")

    test("a day with nothing on it keeps the base pace") {
        let hours = TimeOffAdjustment.hours(forDay: wednesday, basePace: 8, constraints: [])
        expect(hours == 8, "nothing to adjust for, got \(String(describing: hours))")
    }

    test("a weekend has no pace to adjust in the first place") {
        let hours = TimeOffAdjustment.hours(forDay: saturday, basePace: 8, constraints: [])
        expect(hours == nil, "Almanac's own pace calculator never counts a weekend")
    }

    test("a full day off zeroes the pace") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [constraint(start: wednesday)]
        )
        expect(hours == 0, "the whole day is off, got \(String(describing: hours))")
    }

    test("a multi-day constraint spanning the day zeroes it too") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [constraint(start: day("2026-06-15"), end: day("2026-06-19"))]
        )
        expect(hours == 0, "a stretch of vacation covering the day is still the whole day, got \(String(describing: hours))")
    }

    test("a half day off halves the pace") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [constraint(start: wednesday, startTime: "13:00:00", endTime: "17:00:00")]
        )
        expect(hours == 4, "four off an eight-hour day leaves four, got \(String(describing: hours))")
    }

    test("a partial day pro-rates against an assumed eight-hour day, not the base pace") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 6,
            constraints: [constraint(start: wednesday, startTime: "13:00:00", endTime: "17:00:00")]
        )
        // Four of eight assumed hours are off, so six of six remaining
        // becomes three, not six minus four.
        expect(hours == 3, "half of a six-hour pace, got \(String(describing: hours))")
    }

    test("two constraints on the same day take the bigger bite, not the sum") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [
                constraint(id: 1, start: wednesday, startTime: "09:00:00", endTime: "11:00:00"),
                constraint(id: 2, start: wednesday, startTime: "13:00:00", endTime: "17:00:00"),
            ]
        )
        expect(hours == 4, "the larger one wins rather than stacking past zero, got \(String(describing: hours))")
    }

    test("a billable-only constraint is ignored, since the pace here is total hours") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [constraint(start: wednesday, billableOnly: true)]
        )
        expect(hours == 8, "billable-only time off doesn't touch a total-hours pace, got \(String(describing: hours))")
    }

    test("a constraint on some other day leaves this one alone") {
        let hours = TimeOffAdjustment.hours(
            forDay: wednesday,
            basePace: 8,
            constraints: [constraint(start: day("2026-06-18"))]
        )
        expect(hours == 8, "tomorrow's time off doesn't reach back to today, got \(String(describing: hours))")
    }
}
