import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Daily goals")
@MainActor
func runDailyGoalTests() async {
    /// The weekday the test happens to run on, so a goal set for it is the one
    /// today reads back.
    let today = Weekday(Date.now)

    await test("a goal survives a restart") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setGoal(hours: 7.5, breakHours: 0.5, for: .monday)
            expect(state.goalSettings.days[.monday] == DayGoal(hours: 7.5, breakHours: 0.5), "it should be there")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(
                reopened.goalSettings.days[.monday] == DayGoal(hours: 7.5, breakHours: 0.5),
                "it should be read back from disk"
            )
        }
    }

    await test("a goal of nothing leaves the day unset") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setGoal(hours: 8, breakHours: 0.5, for: .friday)
            state.setGoal(hours: 0, breakHours: 0.5, for: .friday)
            expect(state.goalSettings.days[.friday] == nil, "the day should be cleared, not zeroed")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.goalSettings.days[.friday] == nil, "and stay cleared on disk")
        }
    }

    await test("a day with no goal has no progress to report") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(state.goal(forDay: .now) == nil, "nothing is configured yet")
            expect(state.goalProgress(forDay: .now) == nil, "so there is nothing to draw")
            expect(state.todayGoalProgress == nil, "and nothing in the menu bar")
        }
    }

    await test("progress counts the hours tracked against the day's goal") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: Day(Date.now), hours: 3, project: 10, task: 100),
            ])
            let state = AppState(client: fake, storageDirectory: directory)
            await state.sync()
            state.setGoal(hours: 8, breakHours: 0, for: today)

            guard let progress = state.todayGoalProgress else {
                expect(false, "today should have progress once a goal is set")
                return
            }
            expect(progress.workedHours == 3, "three hours tracked, got \(progress.workedHours)")
            expect(progress.remainingHours == 5, "five left, got \(progress.remainingHours)")
            expect(abs(progress.fraction - 0.375) < 0.0001, "three eighths full, got \(progress.fraction)")
            expect(!progress.isMet, "three of eight is not met")
        }
    }

    await test("a gap on the timeline counts as break already taken") {
        try await withTemporaryDirectory { directory in
            let startedAt = Date.now.addingTimeInterval(-90 * 60)
            let fake = FakeHarvest(entries: [
                entry(
                    id: 1,
                    day: Day(Date.now),
                    hours: 1.5,
                    project: 10,
                    task: 100,
                    running: true,
                    startedAt: startedAt
                ),
            ])
            let state = AppState(client: fake, storageDirectory: directory, idleSeconds: { 0 })
            await state.sync()
            state.setGoal(hours: 8, breakHours: 0.5, for: today)

            // The AFK path is how the app cuts a run in two, so it is also the
            // way to put a real gap on the timeline.
            state.afkPrompt = AFKPrompt(
                entryId: 1,
                start: Date.now.addingTimeInterval(-60 * 60),
                end: Date.now.addingTimeInterval(-40 * 60)
            )
            await state.removeAFKTime()

            let taken = state.breakTakenHours(forDay: .now)
            expect(abs(taken - 1.0 / 3) < 0.01, "twenty minutes away is a third of an hour, got \(taken)")

            guard let progress = state.todayGoalProgress else {
                expect(false, "today should have progress once a goal is set")
                return
            }
            expect(
                abs(progress.remainingBreakHours - (0.5 - 1.0 / 3)) < 0.01,
                "ten minutes of break still owed, got \(progress.remainingBreakHours)"
            )
        }
    }

    await test("skipping the break owes none of it, and holds until midnight") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setGoal(hours: 8, breakHours: 0.5, for: today)
            expect(state.todayGoalProgress?.remainingBreakHours == 0.5, "the whole break is owed to start with")

            state.toggleBreakSkip(forDay: .now)
            expect(state.isBreakSkipped(forDay: .now), "today's break should be waved off")
            expect(state.todayGoalProgress?.remainingBreakHours == 0, "so none of it is owed")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.isBreakSkipped(forDay: .now), "and it should hold across a restart")

            let yesterday = Date.now.addingTimeInterval(-24 * 60 * 60)
            expect(
                !reopened.isBreakSkipped(forDay: yesterday),
                "yesterday's marker stops matching on its own"
            )

            state.toggleBreakSkip(forDay: .now)
            expect(!state.isBreakSkipped(forDay: .now), "toggling again puts the break back")
        }
    }

    await test("goals lost to a corrupt file fall back to none") {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "not json".write(
                to: directory.appendingPathComponent("goals.json"),
                atomically: true,
                encoding: .utf8
            )
            let store = GoalsStore(directory: directory)
            expect(store.load() == GoalSettings(), "a file that will not read leaves the app with no goals")
        }
    }
}
