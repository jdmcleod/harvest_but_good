import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Almanac-driven daily pace")
@MainActor
func runAlmanacAppStateTests() async {
    let wednesday = day("2026-06-17").date!
    let email = "ada@rolemodelsoftware.com"

    func connected(_ fake: FakeAlmanac, storageDirectory: URL) -> AppState {
        let state = AppState(client: FakeHarvest(), storageDirectory: storageDirectory, almanacClient: fake)
        state.credentials = Keychain.Credentials(
            token: "harvest-token",
            accountId: "1",
            almanac: AlmanacCredentials(apiKey: "almanac-key", email: email)
        )
        state.setGoalsEnabled(true)
        return state
    }

    await test("Almanac's pace drives the goal once it has answered") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.pace = AlmanacPace(suggestedDailyPace: 8.4, target: 450, worked: 100, remaining: 350, daysIntoReport: 10)
            let state = connected(fake, storageDirectory: directory)

            expect(state.goal(forDay: wednesday) == nil, "nothing until the feature is on")

            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday)?.hours == 8.4, "Almanac's own number, got \(String(describing: state.goal(forDay: wednesday)?.hours))")
        }
    }

    await test("a manual weekday goal is the fallback until Almanac has answered") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0.5, for: Weekday(wednesday))
            state.setAlmanacPaceEnabled(true)
            // Deliberately not synced yet — the fake has never answered.

            expect(state.goal(forDay: wednesday)?.hours == 6, "the hand-set goal fills in until Almanac has something to say")
        }
    }

    await test("turning Almanac's pace off brings the manual goal straight back") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)
            expect(state.goal(forDay: wednesday)?.hours == 8, "Almanac's default pace while it's on")

            state.setAlmanacPaceEnabled(false)
            expect(state.goal(forDay: wednesday)?.hours == 6, "and the manual goal the moment it's off")
        }
    }

    await test("a rejected key turns the feature off quietly, falling back to manual") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.failNextCall = AlmanacAPIError.unauthorized
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 5, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.almanac.isUnavailable, "the book should remember the key was refused")
            expect(state.goal(forDay: wednesday)?.hours == 5, "and the manual goal covers for it")

            // A second refresh should not pester Almanac again.
            let callsBefore = fake.calls.count
            await state.refreshAlmanac(force: true)
            expect(fake.calls.count == callsBefore, "a refusal ends the asking, forced or not")
        }
    }

    await test("break hours come from the manual goal even when Almanac sets the hours") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0.5, for: Weekday(wednesday))
            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)

            let goal = state.goal(forDay: wednesday)
            expect(goal?.hours == 8, "Almanac's hours")
            expect(goal?.breakHours == 0.5, "but the hand-set break, since Almanac has no notion of one")
        }
    }

    await test("Almanac's pace alone, without time off syncing, ignores a day off entirely") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday)?.hours == 8, "the pace switch alone never looks at constraints")
            expect(state.timeOffReason(forDay: wednesday) == nil, "and names no reason, since that switch is off")
        }
    }

    await test("time off syncing alone scales someone's own hand-set pace, not Almanac's") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            // Deliberately no knownPeople and no pace fetch expected — a
            // time-off-only setup should never need a person resolved.
            fake.constraints = [
                constraint(name: "Dentist", start: day("2026-06-17"), startTime: "13:00:00", endTime: "17:00:00"),
            ]
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0.5, for: Weekday(wednesday))
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            // The switch kicks off a refresh of its own alongside the forced
            // one above, so count kinds of call rather than calls.
            expect(
                !fake.calls.isEmpty && fake.calls.allSatisfy { $0 == "constraints(\(email))" },
                "only the constraints were ever asked for, got \(fake.calls)"
            )
            let goal = state.goal(forDay: wednesday)
            expect(goal?.hours == 3, "half of the hand-set six hours, got \(String(describing: goal?.hours))")
            expect(goal?.breakHours == 0.5, "the hand-set break survives the adjustment")
            expect(state.timeOffReason(forDay: wednesday) == "Dentist", "and the reason names the appointment")
        }
    }

    await test("time off syncing alone zeroes a full day off someone's own pace") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday) == nil, "nothing to work toward on a day off")
            expect(state.timeOffReason(forDay: wednesday) == "Vacation", "and the footer can say why")
        }
    }

    await test("with no hand-set goal, time off syncing alone has no base to adjust") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            // No setGoal call — Wednesday is left blank.
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday) == nil, "there was never a goal here to override")
        }
    }

    await test("both switches together scale Almanac's own pace") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [
                constraint(name: "Dentist", start: day("2026-06-17"), startTime: "13:00:00", endTime: "17:00:00"),
            ]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacPaceEnabled(true)
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday)?.hours == 4, "half of Almanac's own eight hours, got \(String(describing: state.goal(forDay: wednesday)?.hours))")
        }
    }

    await test("both switches together zero out a full day off, rather than falling back to the same pace") {
        try await withTemporaryDirectory { directory in
            // The regression this guards: a day scaled to exactly zero used
            // to be treated as "Almanac has nothing to say" and fall back to
            // goalSettings.goal(for:) — which, since almanacPaceEnabled has
            // no hand-set weekday goal of its own to fall back to, read as
            // no goal here too, by coincidence rather than by the right
            // reasoning. The clearer regression is in the test below, where
            // a hand-set goal really is sitting there waiting to leak through.
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacPaceEnabled(true)
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday) == nil, "the whole day is off, got \(String(describing: state.goal(forDay: wednesday)))")
        }
    }

    await test("a full day off doesn't leak the hand-set goal back in when Almanac's pace is also on") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            // A hand-set goal that would wrongly leak through if a zeroed
            // day were mistaken for "Almanac has nothing to say."
            state.setGoal(hours: 6, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacPaceEnabled(true)
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(
                state.goal(forDay: wednesday) == nil,
                "the day off should win, not the hand-set six hours, got \(String(describing: state.goal(forDay: wednesday)))"
            )
        }
    }

    await test("the resolved person id survives a restart, so it isn't looked up every launch") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "42", email: email)]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacPaceEnabled(true)
            await state.refreshAlmanac(force: true)
            expect(state.almanac.personId == "42", "resolved once")

            let secondFake = FakeAlmanac()
            secondFake.knownPeople = [] // would fail to resolve if looked up again
            let reopened = AppState(client: FakeHarvest(), storageDirectory: directory, almanacClient: secondFake)
            reopened.credentials = Keychain.Credentials(
                token: "harvest-token", accountId: "1",
                almanac: AlmanacCredentials(apiKey: "almanac-key", email: email)
            )
            reopened.expireAlmanac()
            await reopened.refreshAlmanac()

            expect(reopened.almanac.personId == "42", "the cached id survived the restart, got \(String(describing: reopened.almanac.personId))")
        }
    }

    await test("re-saving the same key and email doesn't clear the cached constraints") {
        try await withTemporaryDirectory { directory in
            // A constraint ending today drops out of Almanac's own
            // next_constraints the moment its end date isn't strictly in the
            // future, so the cache from an earlier fetch is the only place
            // it survives — see AlmanacBook.received. A save that wipes the
            // cache on every call (what every Sync Now click and every field
            // blur used to do, whether or not anything changed) throws that
            // constraint away right when it's needed.
            let fake = FakeAlmanac()
            fake.constraints = [constraint(name: "Ends today", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)
            expect(state.almanac.constraints.count == 1, "the constraint synced")

            // Almanac stops returning it from here on, the way it would once
            // today passes its end date — the cache is now the only copy.
            fake.constraints = []
            try state.saveAlmanacCredentials(apiKey: "almanac-key", email: email)

            expect(
                state.almanac.constraints.count == 1,
                "re-saving the same identity shouldn't have cleared the cache, got \(state.almanac.constraints.count)"
            )
        }
    }

    await test("saving a genuinely different identity does clear the cache") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.constraints = [constraint(name: "Someone else's", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacTimeOffEnabled(true)
            await state.refreshAlmanac(force: true)
            expect(state.almanac.constraints.count == 1, "the constraint synced")

            try state.saveAlmanacCredentials(apiKey: "a-different-key", email: "someone.else@rolemodelsoftware.com")

            expect(
                state.almanac.constraints.isEmpty,
                "a new identity has no business keeping the old one's cached time off"
            )
        }
    }
}
