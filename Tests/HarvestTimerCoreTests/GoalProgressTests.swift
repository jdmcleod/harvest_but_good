import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Progress against a day's goal")
func runGoalProgressTests() {
    /// A day part worked, with a break allowance and however much of it taken.
    func progress(
        goal: Double = 8,
        worked: Double,
        allowance: Double = 0,
        taken: Double = 0,
        skipped: Bool = false
    ) -> GoalProgress {
        GoalProgress(
            goalHours: goal,
            workedHours: worked,
            breakAllowanceHours: allowance,
            breakTakenHours: taken,
            breakSkipped: skipped
        )
    }

    /// How far past `base` a finish time lands, in hours.
    func hoursOut(_ finish: Date?) -> Double? {
        finish.map { $0.timeIntervalSince(base) / 3600 }
    }

    test("the fraction is how full the day is, and never leaves 0 through 1") {
        expect(progress(worked: 0).fraction == 0, "an untouched day is empty")
        expect(progress(worked: 4).fraction == 0.5, "half a day is half full")
        expect(progress(worked: 8).fraction == 1, "a met goal is full")
        expect(progress(worked: 12).fraction == 1, "an overrun still reads full, got \(progress(worked: 12).fraction)")
        expect(progress(worked: -1).fraction == 0, "a negative total cannot draw backwards")
    }

    test("a goal of nothing is handled rather than divided by") {
        let none = progress(goal: 0, worked: 3)
        expect(none.fraction == 0, "no goal, nothing to fill")
        expect(!none.isMet, "a goal of nothing is not a goal met")
        expect(none.finishTime(from: base) == nil, "there is no time to work until")
    }

    test("hours left run down to nothing and no further") {
        expect(progress(worked: 3).remainingHours == 5, "five of eight left")
        expect(progress(worked: 8).remainingHours == 0, "a met goal has nothing left")
        expect(progress(worked: 9.5).remainingHours == 0, "an overrun is not owed back")
    }

    test("a goal met is met, and has no finish time") {
        expect(progress(worked: 8).isMet, "worked exactly the goal counts as met")
        expect(progress(worked: 8.25).isMet, "worked past the goal counts as met")
        expect(!progress(worked: 7.99).isMet, "just short is not met")
        expect(progress(worked: 8).finishTime(from: base) == nil, "nothing left to work until")
    }

    test("the finish time is the hours left plus the break still owed") {
        expect(hoursOut(progress(worked: 3).finishTime(from: base)) == 5, "no break, five hours out")
        expect(
            hoursOut(progress(worked: 3, allowance: 0.5).finishTime(from: base)) == 5.5,
            "a half hour break owed pushes the finish out by a half hour"
        )
    }

    test("a break already taken no longer pushes the finish out") {
        let part = progress(worked: 3, allowance: 0.5, taken: 0.25)
        expect(part.remainingBreakHours == 0.25, "a quarter hour of break still owed")
        expect(hoursOut(part.finishTime(from: base)) == 5.25, "only the remainder pushes the finish out")

        let whole = progress(worked: 3, allowance: 0.5, taken: 0.5)
        expect(whole.remainingBreakHours == 0, "the break has been had")
        expect(hoursOut(whole.finishTime(from: base)) == 5, "nothing left to pad with")

        let more = progress(worked: 3, allowance: 0.5, taken: 2)
        expect(more.remainingBreakHours == 0, "a long lunch does not owe break time back")
    }

    test("a skipped break pushes nothing out, however little was taken") {
        let skipped = progress(worked: 3, allowance: 0.5, skipped: true)
        expect(skipped.remainingBreakHours == 0, "waved off means none owed")
        expect(hoursOut(skipped.finishTime(from: base)) == 5, "the finish time is the hours left alone")
    }
}
