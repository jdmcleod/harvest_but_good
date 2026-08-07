import Foundation
import HarvestTimerCore

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

@MainActor
func runAppStateTests() async {
    let calendar = Calendar.current

    await test("liveHours adds the time since the last sync to a running entry") {
        try await withTemporaryDirectory { directory in
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let days = state.weekDays.map(state.dayString)
            expect(
                days == ["2025-08-04", "2025-08-05", "2025-08-06", "2025-08-07", "2025-08-08"],
                "expected Monday through Friday, got \(days)"
            )

            // A Monday and a Friday should both land on the same week.
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 4))!
            expect(state.weekDays.map(state.dayString) == days, "Monday should give the same week")
            state.selectedDay = calendar.date(from: DateComponents(year: 2025, month: 8, day: 8))!
            expect(state.weekDays.map(state.dayString) == days, "Friday should give the same week")
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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

    await test("moving the whole entry deletes the source") {
        try await withTemporaryDirectory { directory in
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
            let today = dayName(.now)
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
