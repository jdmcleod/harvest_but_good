import Foundation
import Testing

@testable import HarvestTimerCore

/// Builds a state wired to `fake`, synced once so it holds the fake's entries.
@MainActor
private func syncedState(
    _ fake: FakeHarvest,
    directory: URL,
    selecting day: Date = .now
) async -> AppState {
    let state = AppState(client: fake, storageDirectory: directory)
    state.selectedDay = day
    await state.sync()
    return state
}

@Test("AppState")
@MainActor
func runAppStateTests() async {
    let calendar = Calendar.current

    await test("liveHours adds the time since the last sync to a running entry") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100, running: true),
                entry(id: 2, day: today, hours: 2, project: 11, task: 110),
            ])
            let state = await syncedState(fake, directory: directory)
            let running = state.entry(withId: 1)!
            expect(state.liveHours(for: running) == 1, "at sync time a running entry has its own hours")

            state.now = state.lastSyncAt.addingTimeInterval(1800)
            expect(state.liveHours(for: running) == 1.5, "half an hour later it should read 1.5")
            expect(state.liveHours(for: state.entry(withId: 2)!) == 2, "a stopped entry should not move")
            expect(state.total(forDay: .now) == 3.5, "the day total should include the live time")
            expect(state.menuBarTitle == "1:30", "the menu bar should show the running entry")
        }
    }

    await test("the menu bar falls back to the day total with nothing running") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1.25, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)
            expect(state.menuBarTitle == "1:15", "expected the day total, got \(state.menuBarTitle)")
        }
    }

    await test("the week runs Monday to Friday whatever day is selected") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            // 6 August 2025 is a Wednesday.
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 6))!
            let days = state.weekDays.map { Day($0).name }
            expect(
                days == ["2025-08-04", "2025-08-05", "2025-08-06", "2025-08-07", "2025-08-08"],
                "expected Monday through Friday, got \(days)"
            )

            // A Monday and a Friday should both land on the same week.
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 4))!
            expect(state.weekDays.map { Day($0).name } == days, "Monday should give the same week")
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 8))!
            expect(state.weekDays.map { Day($0).name } == days, "Friday should give the same week")
        }
    }

    await test("today is only the day the clock is in") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            // Thursday 7 August 2025, so the week runs 4th to 8th.
            state.now = calendar.date(from: DateComponents(year: 2025, month: 8, day: 7))!
            state.selectedDay = state.now
            expect(state.isViewingToday, "the clock's own day is today")

            // The whole point of the button: another day of this same week is
            // somewhere to come back from, where the week check said otherwise.
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 4))!
            expect(!state.isViewingToday, "Monday of this week is not today")
            expect(state.isToday(state.now), "Thursday is still today whatever is selected")

            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 1))!
            expect(!state.isViewingToday, "a day in the week before is not today")
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 11))!
            expect(!state.isViewingToday, "a day in the week after is not today")
        }
    }

    await test("the day tabs read today off the app's clock, not the system's") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.now = calendar.date(from: DateComponents(year: 2025, month: 8, day: 7))!
            let thursday = calendar.date(from: DateComponents(year: 2025, month: 8, day: 7, hour: 23))!
            expect(state.isToday(thursday), "any hour of the clock's day counts as today")
            expect(
                !state.isToday(.now),
                "the real date should not read as today while the clock sits in 2025"
            )
        }
    }

    await test("going back to today lands on today") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.now = calendar.date(from: DateComponents(year: 2025, month: 8, day: 7))!
            // Two weeks back, on a Tuesday rather than today's Thursday.
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 7, day: 22))!
            expect(!state.isViewingToday, "the setup should start away from today")

            state.goToToday()
            expect(
                calendar.isDate(state.selectedDay, inSameDayAs: state.now),
                "expected today, got \(Day(state.selectedDay).name)"
            )
            expect(state.isViewingToday, "and the way back should stop being on offer")
        }
    }

    await test("going back to today from another day of this same week") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.now = calendar.date(from: DateComponents(year: 2025, month: 8, day: 7))!
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 5))!
            expect(!state.isViewingToday, "Tuesday of this week is somewhere to come back from")

            state.goToToday()
            expect(
                calendar.isDate(state.selectedDay, inSameDayAs: state.now),
                "expected today, got \(Day(state.selectedDay).name)"
            )
        }
    }

    await test("weekly totals sum the whole week, billable entries separately") {
        try await withTemporaryDirectory { directory in
            let wednesday = calendar.date(from: DateComponents(year: 2025, month: 8, day: 6))!
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: Day(name: "2025-08-04")!, hours: 2, project: 10, task: 100, billable: true),
                entry(id: 2, day: Day(name: "2025-08-06")!, hours: 1.5, project: 11, task: 110),
                entry(id: 3, day: Day(name: "2025-08-08")!, hours: 0.5, project: 10, task: 100, billable: true),
            ])
            let state = await syncedState(fake, directory: directory, selecting: wednesday)
            expect(state.weekTotal == 4, "expected 4 hours across the week, got \(state.weekTotal)")
            expect(state.weekBillableTotal == 2.5, "expected 2.5 billable hours, got \(state.weekBillableTotal)")
        }
    }

    await test("selecting a different day clears the selected entry") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.selectedEntryId = 42
            state.selectedDay = calendar.date(byAdding: .day, value: -1, to: state.selectedDay)!
            expect(state.selectedEntryId == nil, "the selection should not survive a day change")
        }
    }

    await test("starting a timer reuses the day's entry for that project and task") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.startTimer(projectId: 10, taskId: 100)
            expect(fake.calls.contains("restart(1)"), "should restart the entry it already has")
            expect(!fake.calls.contains { $0.hasPrefix("startTimer") }, "should not create a second entry")
            expect(fake.runningEntry?.id == 1, "entry 1 should be running")

            await state.startTimer(projectId: 20, taskId: 200)
            expect(
                fake.calls.contains("startTimer(project: 20, task: 200)"),
                "an unseen project should get a fresh entry"
            )
            expect(fake.runningEntry?.project.id == 20, "the new entry should be the running one")
            expect(fake.entry(1)?.isRunning == false, "starting one timer should stop the other")
        }
    }

    await test("start counts come from the app's own starts") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)
            expect(state.startCounts(forDay: .now)[1] == nil, "no starts yet")

            await state.startTimer(projectId: 10, taskId: 100)
            await state.toggle(state.entry(withId: 1)!)
            await state.startTimer(projectId: 10, taskId: 100)
            expect(state.startCounts(forDay: .now)[1] == 2, "two starts of entry 1")
        }
    }

    await test("editing an entry's duration marks it modified for the timeline") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)
            expect(state.modifiedEntryIds(forDay: .now).isEmpty, "nothing edited yet")

            await state.updateHours(state.entry(withId: 1)!, hours: 2)
            expect(fake.entry(1)?.hours == 2, "hours should reach Harvest")
            expect(state.entry(withId: 1)?.hours == 2, "the local copy should follow")
            expect(state.modifiedEntryIds(forDay: .now) == [1], "the edit should be logged")
        }
    }

    await test("changing an entry's project keeps its hours") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1.5, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.updateProjectTask(state.entry(withId: 1)!, projectId: 20, taskId: 200)
            expect(state.entry(withId: 1)?.project.id == 20, "project should change")
            expect(state.entry(withId: 1)?.hours == 1.5, "hours should be untouched")

            let callsBefore = fake.calls.count
            await state.updateProjectTask(state.entry(withId: 1)!, projectId: 20, taskId: 200)
            expect(fake.calls.count == callsBefore, "setting the same project should not call Harvest")
        }
    }

    await test("deleting an entry drops it locally and logs the deletion") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100),
                entry(id: 2, day: today, hours: 2, project: 11, task: 110),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.deleteEntry(state.entry(withId: 1)!)
            expect(fake.entry(1) == nil, "the entry should be gone from Harvest")
            expect(state.entry(withId: 1) == nil, "and gone locally")
            expect(state.entries(forDay: .now).map(\.id) == [2], "the other entry should remain")
            expect(state.modifiedEntryIds(forDay: .now) == [1], "the deletion should be logged")
        }
    }

    await test("a failed call surfaces as a sync error and leaves the entry alone") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            fake.failNextCall = FakeHarvest.FakeError.noSuchEntry
            await state.updateHours(state.entry(withId: 1)!, hours: 5)
            expect(state.syncError != nil, "the failure should be reported")
            expect(state.entry(withId: 1)?.hours == 1, "the local copy should not have changed")

            await state.sync()
            expect(state.syncError == nil, "a good sync should clear the error")
        }
    }

    await runMoveTimeStateTests()
}

/// moveTime splits an entry, merges or creates the destination, and hands a
/// running timer to whichever side kept the time. Worth covering closely.
@MainActor
private func runMoveTimeStateTests() async {
    await test("moving part of an entry to a new project creates the destination") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100, notes: "Debugging"),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 0.5, projectId: 20, taskId: 200)

            expect(fake.entry(1)?.hours == 1.5, "the source should keep the rest, got \(fake.entry(1)!.hours)")
            let destination = fake.entries.values.first { $0.project.id == 20 }
            expect(destination?.hours == 0.5, "the destination should hold the moved time")
            expect(destination?.notes == "Debugging", "notes should come along to a fresh entry")
            expect(state.total(forDay: .now) == 2, "the day total should not change")
        }
    }

    await test("moving onto an entry that already exists merges into it") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100),
                entry(id: 2, day: today, hours: 1, project: 20, task: 200),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 0.5, projectId: 20, taskId: 200)

            expect(fake.entry(2)?.hours == 1.5, "the destination should absorb the time")
            expect(fake.entry(1)?.hours == 1.5, "the source should keep the rest")
            expect(fake.entries.count == 2, "no third entry should appear")
            expect(
                !fake.calls.contains { $0.hasPrefix("createEntry") },
                "merging should not create an entry"
            )
            expect(state.total(forDay: .now) == 3, "the day total should not change")
        }
    }

    await test("naming a destination entry lands on it, even sharing the source's project and task") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100, notes: "rates stuff"),
                entry(id: 2, day: today, hours: 1, project: 10, task: 100, notes: "meeting"),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(
                state.entry(withId: 1)!,
                hours: 0.5,
                projectId: 10,
                taskId: 100,
                destinationEntryId: 2
            )

            expect(fake.entry(2)?.hours == 1.5, "the named entry should absorb the time")
            expect(fake.entry(1)?.hours == 1.5, "the source should keep the rest")
            expect(fake.entries.count == 2, "no third entry should appear")
        }
    }

    await test("a partial move restarts the source entry itself, not an unnamed copy") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100, running: true, notes: "rates stuff"),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 0.5, projectId: 20, taskId: 200)

            expect(fake.calls.contains("restart(1)"), "the source should pick its own timer back up")
            expect(fake.entries.count == 2, "only the destination should be new, got \(fake.entries.count)")
            expect(fake.runningEntry?.id == 1, "the source should be the one running")
            expect(fake.entry(1)?.notes == "rates stuff", "its notes should survive")
        }
    }

    await test("moving the whole entry deletes the source") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 2, projectId: 20, taskId: 200)

            expect(fake.entry(1) == nil, "the emptied source should be deleted")
            expect(state.entry(withId: 1) == nil, "and gone locally too")
            let destination = fake.entries.values.first { $0.project.id == 20 }
            expect(destination?.hours == 2, "the destination should hold all of it")
            expect(state.total(forDay: .now) == 2, "the day total should not change")
        }
    }

    await test("asking to move more than the entry holds moves all of it") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 0.75, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 5, projectId: 20, taskId: 200)

            expect(fake.entry(1) == nil, "the source should be emptied and deleted")
            expect(
                fake.entries.values.first { $0.project.id == 20 }?.hours == 0.75,
                "the destination should get exactly what the source had"
            )
        }
    }

    await test("a running source is stopped before the split, and keeps running") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100, running: true),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 0.5, projectId: 20, taskId: 200)

            let stopIndex = fake.calls.firstIndex(of: "stop(1)")
            let createIndex = fake.calls.firstIndex { $0.hasPrefix("createEntry") }
            expect(stopIndex != nil, "the timer should be stopped first")
            expect(
                stopIndex! < createIndex!,
                "the split should work off a settled number, got \(fake.calls)"
            )
            expect(fake.entry(1)?.hours == 1.5, "the source should keep the rest")
            expect(fake.runningEntry?.id == 1, "time is left on the source, so it keeps the timer")
        }
    }

    await test("emptying a running source hands the timer to the destination") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100, running: true),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 2, projectId: 20, taskId: 200)

            expect(fake.entry(1) == nil, "the emptied source should be gone")
            expect(fake.runningEntry?.project.id == 20, "the destination should be running")
            expect(state.runningEntry?.project.id == 20, "and the state should agree")
        }
    }

    await test("a move to the entry's own project and task does nothing") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)
            let callsBefore = fake.calls.count

            await state.moveTime(state.entry(withId: 1)!, hours: 1, projectId: 10, taskId: 100)

            expect(fake.calls.count == callsBefore, "moving onto itself should not call Harvest")
            expect(fake.entry(1)?.hours == 2, "the entry should be untouched")
        }
    }

    await test("moving nothing does nothing") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100),
                entry(id: 2, day: today, hours: 0, project: 11, task: 110),
            ])
            let state = await syncedState(fake, directory: directory)
            let callsBefore = fake.calls.count

            await state.moveTime(state.entry(withId: 1)!, hours: 0, projectId: 20, taskId: 200)
            expect(fake.calls.count == callsBefore, "a zero move should not call Harvest")

            // An entry with no time on it has nothing to give.
            await state.moveTime(state.entry(withId: 2)!, hours: 1, projectId: 20, taskId: 200)
            expect(fake.calls.count == callsBefore, "an empty source should not call Harvest")
        }
    }

    await test("a move logs an edit so the timeline can stripe the entry") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 2, project: 10, task: 100),
            ])
            let state = await syncedState(fake, directory: directory)

            await state.moveTime(state.entry(withId: 1)!, hours: 0.5, projectId: 20, taskId: 200)
            expect(
                state.modifiedEntryIds(forDay: .now).contains(1),
                "the shrunk source should show as edited"
            )
        }
    }
}

@Test("The AFK loop")
@MainActor
func runAFKLoopTests() async {
    await test("a turn of the AFK loop raises a prompt for the running entry") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(id: 1, day: today, hours: 1, project: 10, task: 100, running: true),
            ])
            var announced = 0
            let state = AppState(
                client: fake,
                storageDirectory: directory,
                idleSeconds: { 0 }
            )
            state.onAFKDetected = { announced += 1 }
            await state.sync()

            state.afkTick()
            expect(state.afkPrompt == nil, "no prompt while the keyboard is busy")

            // The prompt comes on the way back: input seen now, with a gap
            // since the input before it. Putting the last one in the past is
            // the same thing as having walked away for that long.
            let away = Double(state.afkToleranceMinutes) * 60 + 60
            state.lastActivityAt = Date.now.addingTimeInterval(-away)
            state.afkTick()
            expect(state.afkPrompt?.entryId == 1, "the running entry should be the one queried")
            expect(
                state.afkPrompt.map { $0.duration >= away - 5 } == true,
                "the prompt should cover the whole time away, got \(state.afkPrompt?.duration ?? -1)"
            )
            expect(announced == 1, "the app should be told once, so it can show the window")

            state.afkTick()
            expect(announced == 1, "a prompt already up should not be announced again")

            state.dismissAFKPrompt()
            expect(state.afkPrompt == nil, "dismissing should clear it")
        }
    }

    await test("a break taken before the timer started raises no prompt") {
        try await withTemporaryDirectory { directory in
            let today = Day(.now)
            let fake = FakeHarvest(entries: [
                entry(
                    id: 1,
                    day: today,
                    hours: 1,
                    project: 10,
                    task: 100,
                    running: true,
                    startedAt: .now
                ),
            ])
            let state = AppState(client: fake, storageDirectory: directory, idleSeconds: { 0 })
            await state.sync()

            let away = Double(state.afkToleranceMinutes) * 60 + 60
            state.lastActivityAt = Date.now.addingTimeInterval(-away)
            state.afkTick()
            expect(state.afkPrompt == nil, "the break happened before the timer was on")
        }
    }

    await test("the first open of the day lands on today") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!

            state.selectedDay = yesterday
            state.windowDidOpen()
            expect(
                Calendar.current.isDate(state.selectedDay, inSameDayAs: yesterday),
                "a second open the same day should leave the chosen day alone"
            )

            state.lastOpenedAt = yesterday
            state.windowDidOpen()
            expect(
                Calendar.current.isDateInToday(state.selectedDay),
                "the first open of a new day should jump to today"
            )
        }
    }

    await test("a synced state can point at a project's page on the Harvest site") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            let state = AppState(client: fake, storageDirectory: directory)
            expect(state.projectURL(for: 10) == nil, "before a sync the account's address is unknown")

            await state.sync()
            expect(
                state.projectURL(for: 10) == URL(string: "https://testco.harvestapp.com/projects/10"),
                "got \(String(describing: state.projectURL(for: 10)))"
            )

            await state.sync()
            let fetches = fake.calls.filter { $0 == "company" }
            expect(fetches.count == 1, "the address should be asked for once, asked \(fetches.count) times")

            state.removeCredentials()
            expect(state.projectURL(for: 10) == nil, "the address should go with the token")
        }
    }

    await test("a turn of the AFK loop moves the clock on") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.now = .distantPast
            state.afkTick()
            expect(state.now.timeIntervalSinceNow > -1, "the tick should bring `now` up to date")
        }
    }
}

private func budget(
    project: Int64,
    by budgetBy: String = "project",
    budget total: Double?,
    spent: Double?,
    remaining: Double?
) -> ProjectBudget {
    ProjectBudget(
        projectId: project,
        budgetBy: budgetBy,
        budget: total,
        budgetSpent: spent,
        budgetRemaining: remaining
    )
}

@Test("Project budgets")
@MainActor
func runProjectBudgetTests() async {
    await test("a sync brings the budgets in, keyed by project") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            fake.budgets = [
                budget(project: 10, budget: 40, spent: 27.5, remaining: 12.5),
                budget(project: 11, by: "project_cost", budget: 10000, spent: 5800, remaining: 4200),
            ]
            let state = await syncedState(fake, directory: directory)
            expect(state.projectBudgets[10]?.budgetRemaining == 12.5, "project 10's budget should be there")
            expect(state.projectBudgets[11]?.budgetIsMonetary == true, "so should project 11's")
        }
    }

    await test("budgets are not asked for again inside the refresh interval") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            let state = await syncedState(fake, directory: directory)
            await state.sync()
            let fetches = fake.calls.filter { $0 == "projectBudgets" }
            expect(fetches.count == 1, "two syncs close together should fetch once, fetched \(fetches.count) times")

            state.lastBudgetFetchAt = Date.now.addingTimeInterval(-AppState.budgetRefreshInterval - 1)
            await state.sync()
            let after = fake.calls.filter { $0 == "projectBudgets" }
            expect(after.count == 2, "past the interval a sync should fetch again, fetched \(after.count) times")
        }
    }

    await test("a token without budget access turns the feature off quietly") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            fake.budgetsError = HarvestAPIError.forbidden
            let state = await syncedState(fake, directory: directory)
            expect(state.projectBudgets.isEmpty, "nothing should be shown")
            expect(state.syncError == nil, "a missing role is not an error worth a banner")

            await state.sync()
            let fetches = fake.calls.filter { $0 == "projectBudgets" }
            expect(fetches.count == 1, "the 403 should not be asked for again, fetched \(fetches.count) times")
        }
    }

    await test("other budget failures keep what was shown and stay quiet") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            fake.budgets = [budget(project: 10, budget: 40, spent: 20, remaining: 20)]
            let state = await syncedState(fake, directory: directory)
            expect(state.projectBudgets[10] != nil, "the first fetch should land")

            fake.budgetsError = HarvestAPIError.network(URLError(.timedOut))
            state.lastBudgetFetchAt = .distantPast
            await state.sync()
            expect(state.projectBudgets[10] != nil, "a flaky fetch should not blank the bars")
            expect(state.syncError == nil, "and should not raise the banner")
        }
    }

    await test("removing the token clears the budgets") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            fake.budgets = [budget(project: 10, budget: 40, spent: 20, remaining: 20)]
            let state = await syncedState(fake, directory: directory)
            expect(!state.projectBudgets.isEmpty, "the budgets should be there first")

            state.removeCredentials()
            expect(state.projectBudgets.isEmpty, "and gone with the token")
            expect(state.lastBudgetFetchAt == nil, "along with the fetch stamp")
        }
    }

    test("the summary gives what remains, compactly, with its share of the budget") {
        let money = budget(project: 1, by: "project_cost", budget: 10000, spent: 5800, remaining: 4200)
        expect(
            money.remainingSummary == "Budget remaining: $4.2k (42%)",
            "got \(money.remainingSummary ?? "nil")"
        )

        let round = budget(project: 1, by: "project_cost", budget: 10000, spent: 6000, remaining: 4000)
        expect(
            round.remainingSummary == "Budget remaining: $4k (40%)",
            "a round figure should not carry a decimal, got \(round.remainingSummary ?? "nil")"
        )

        let small = budget(project: 1, by: "project_cost", budget: 2000, spent: 1050, remaining: 950)
        expect(
            small.remainingSummary == "Budget remaining: $950 (48%)",
            "under a thousand stays in plain dollars, got \(small.remainingSummary ?? "nil")"
        )

        let hours = budget(project: 1, budget: 40, spent: 27.5, remaining: 12.5)
        expect(
            hours.remainingSummary == "Budget remaining: 12.5h (31%)",
            "got \(hours.remainingSummary ?? "nil")"
        )

        let over = budget(project: 1, by: "project_cost", budget: 10000, spent: 10500, remaining: -500)
        expect(
            over.remainingSummary == "Over budget by $500",
            "got \(over.remainingSummary ?? "nil")"
        )

        let none = budget(project: 1, budget: nil, spent: nil, remaining: nil)
        expect(none.remainingSummary == nil, "no budget, no summary")
        expect(none.remainingDescription == nil, "and nothing to describe")

        let zero = budget(project: 1, budget: 0, spent: 5, remaining: -5)
        expect(zero.remainingSummary == nil, "a zero budget makes no summary")
    }

    test("the description talks in hours or money to match the budget") {
        let hours = budget(project: 1, budget: 40, spent: 27.5, remaining: 12.5)
        expect(
            hours.remainingDescription == "12.5h left of 40h",
            "got \(hours.remainingDescription ?? "nil")"
        )

        let money = budget(project: 1, by: "project_cost", budget: 10000, spent: 5800, remaining: 4200)
        expect(
            money.remainingDescription == "$4,200 left of $10,000",
            "got \(money.remainingDescription ?? "nil")"
        )

        let over = budget(project: 1, budget: 40, spent: 42, remaining: -2)
        expect(
            over.remainingDescription == "2h over the 40h budget",
            "got \(over.remainingDescription ?? "nil")"
        )
    }
}

@Test("Break titles")
@MainActor
func runBreakTitleTests() async {
    await test("a break's title survives a restart") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setBreakTitle("Lunch", forBreakId: "break-123")
            expect(state.breakTitle(forBreakId: "break-123") == "Lunch", "the title should be there")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(
                reopened.breakTitle(forBreakId: "break-123") == "Lunch",
                "it should be read back from disk"
            )
        }
    }

    await test("a blank title takes the name away") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setBreakTitle("Lunch", forBreakId: "break-123")
            state.setBreakTitle("   ", forBreakId: "break-123")
            expect(state.breakTitle(forBreakId: "break-123") == nil, "the title should be gone")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.breakTitle(forBreakId: "break-123") == nil, "and stay gone on disk")
        }
    }

    await test("a title is trimmed before it is kept") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.setBreakTitle("  Walk the dog  ", forBreakId: "break-9")
            expect(state.breakTitle(forBreakId: "break-9") == "Walk the dog", "whitespace should go")
        }
    }
}

@Test("Favorites")
@MainActor
func runFavoritesTests() async {
    let favorite = Favorite(
        projectId: 10,
        taskId: 100,
        clientName: "Client",
        projectName: "Project 10",
        taskName: "Development"
    )

    await test("favorites survive a restart") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.addFavorite(favorite)
            expect(state.favorites.count == 1, "the favorite should be there")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.favorites == [favorite], "it should be read back from disk")

            reopened.removeFavorite(favorite)
            let again = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(again.favorites.isEmpty, "removing it should stick too")
        }
    }

    await test("toggling a favorite adds it, toggling again removes it") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(!state.isFavorite(projectId: favorite.projectId, taskId: favorite.taskId), "nothing is a favorite yet")

            state.toggleFavorite(favorite)
            expect(state.favorites == [favorite], "the first toggle should add it")
            expect(state.isFavorite(projectId: favorite.projectId, taskId: favorite.taskId), "it should now report as a favorite")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.favorites == [favorite], "the toggled favorite should survive a restart")

            reopened.toggleFavorite(favorite)
            expect(reopened.favorites.isEmpty, "the second toggle should remove it")

            let again = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(again.favorites.isEmpty, "the removal should survive a restart too")
        }
    }

    await test("an empty or missing favorites file is not a failure") {
        try await withTemporaryDirectory { directory in
            let store = FavoritesStore(directory: directory)
            expect(store.load().isEmpty, "a missing file should read as empty")

            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: directory.appendingPathComponent("favorites.json"))
            expect(store.load().isEmpty, "unreadable contents should read as empty")
        }
    }

    await test("the same favorite is not added twice, even after a rename") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.addFavorite(favorite)
            state.addFavorite(favorite)
            expect(state.favorites.count == 1, "adding it again should do nothing")

            // Harvest renamed the project. It is the same project and task.
            let renamed = Favorite(
                projectId: favorite.projectId,
                taskId: favorite.taskId,
                clientName: favorite.clientName,
                projectName: "Project 10 — 2026 Maintenance",
                taskName: favorite.taskName
            )
            state.addFavorite(renamed)
            expect(state.favorites.count == 1, "a rename should not make a second favorite")

            state.removeFavorite(renamed)
            expect(state.favorites.isEmpty, "removing by the renamed copy should still work")
        }
    }

    await test("reordering favorites survives a restart") {
        try await withTemporaryDirectory { directory in
            let second = Favorite(
                projectId: 11,
                taskId: 110,
                clientName: "Client",
                projectName: "Project 11",
                taskName: "Development"
            )
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.addFavorite(favorite)
            state.addFavorite(second)

            state.moveFavorite(from: 0, to: 1)
            expect(state.favorites == [second, favorite], "the chips should have swapped")

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.favorites == [second, favorite], "the new order should be read back from disk")

            reopened.moveFavorite(from: 0, to: 0)
            expect(reopened.favorites == [second, favorite], "moving a chip onto itself should change nothing")

            reopened.moveFavorite(from: 0, to: 5)
            expect(reopened.favorites == [second, favorite], "an index off the end should change nothing")
        }
    }

    await test("a nickname and colour survive a restart, and keep their place") {
        try await withTemporaryDirectory { directory in
            let second = Favorite(
                projectId: 11,
                taskId: 110,
                clientName: "Client",
                projectName: "Project 11",
                taskName: "Development"
            )
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            state.addFavorite(favorite)
            state.addFavorite(second)

            var edited = favorite
            edited.nickname = "Admin"
            edited.colorIndex = 3
            state.updateFavorite(edited)

            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory)
            expect(reopened.favorites.count == 2, "editing should not add or drop a favorite")
            expect(reopened.favorites.first?.nickname == "Admin", "the nickname should be read back from disk")
            expect(reopened.favorites.first?.colorIndex == 3, "the colour should be read back from disk")
            expect(reopened.favorites.last == second, "the edited chip should have kept its place")

            let unknown = Favorite(
                projectId: 99,
                taskId: 990,
                clientName: "Client",
                projectName: "Project 99",
                taskName: "Development",
                nickname: "Nope"
            )
            reopened.updateFavorite(unknown)
            expect(reopened.favorites.count == 2, "editing a favorite that is not there should do nothing")
        }
    }

    await test("a favorites file written before nicknames existed still loads") {
        try await withTemporaryDirectory { directory in
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let old = """
            [{"projectId":10,"taskId":100,"clientName":"Client",\
            "projectName":"Client – Project 10","taskName":"Development"}]
            """
            try Data(old.utf8).write(to: directory.appendingPathComponent("favorites.json"))

            let loaded = FavoritesStore(directory: directory).load()
            expect(loaded.count == 1, "the old shape should still decode, got \(loaded.count)")
            expect(loaded.first?.nickname == nil, "a file without a nickname should read as no nickname")
            expect(loaded.first?.colorIndex == nil, "a file without a colour should read as no colour")
            expect(loaded.first?.chipLabel == "PROJEC", "it should fall back to the derived label")
        }
    }

    await test("starting a favorite starts its project and task") {
        try await withTemporaryDirectory { directory in
            let fake = FakeHarvest()
            let state = AppState(client: fake, storageDirectory: directory)
            await state.startFavorite(favorite)
            expect(
                fake.calls.contains("startTimer(project: 10, task: 100)"),
                "expected a start for the favorite, got \(fake.calls)"
            )
        }
    }
}
