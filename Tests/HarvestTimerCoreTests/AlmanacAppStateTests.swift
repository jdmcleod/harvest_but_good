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
        return state
    }

    await test("Almanac's pace drives the goal once it has answered") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.pace = AlmanacPace(suggestedDailyPace: 8.4, target: 450, worked: 100, remaining: 350, daysIntoReport: 10)
            let state = connected(fake, storageDirectory: directory)

            expect(state.goal(forDay: wednesday) == nil, "nothing until the feature is on")

            state.setAlmanacEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday)?.hours == 8.4, "Almanac's own number, got \(String(describing: state.goal(forDay: wednesday)?.hours))")
        }
    }

    await test("a manual weekday goal is the fallback until Almanac has answered") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0.5, for: Weekday(wednesday))
            state.setAlmanacEnabled(true)
            // Deliberately not synced yet — the fake has never answered.

            expect(state.goal(forDay: wednesday)?.hours == 6, "the hand-set goal fills in until Almanac has something to say")
        }
    }

    await test("turning Almanac off brings the manual goal straight back") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 6, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacEnabled(true)
            await state.refreshAlmanac(force: true)
            expect(state.goal(forDay: wednesday)?.hours == 8, "Almanac's default pace while it's on")

            state.setAlmanacEnabled(false)
            expect(state.goal(forDay: wednesday)?.hours == 6, "and the manual goal the moment it's off")
        }
    }

    await test("a rejected key turns the feature off quietly, falling back to manual") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.failNextCall = AlmanacAPIError.unauthorized
            let state = connected(fake, storageDirectory: directory)
            state.setGoal(hours: 5, breakHours: 0, for: Weekday(wednesday))
            state.setAlmanacEnabled(true)
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
            state.setAlmanacEnabled(true)
            await state.refreshAlmanac(force: true)

            let goal = state.goal(forDay: wednesday)
            expect(goal?.hours == 8, "Almanac's hours")
            expect(goal?.breakHours == 0.5, "but the hand-set break, since Almanac has no notion of one")
        }
    }

    await test("a full day off leaves no goal, and names the reason") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [constraint(name: "Vacation", start: day("2026-06-17"))]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday) == nil, "nothing to work toward on a day off")
            expect(state.timeOffReason(forDay: wednesday) == "Vacation", "and the footer can say why")
        }
    }

    await test("a half day off scales the pace and still names the reason") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "1", email: email)]
            fake.constraints = [
                constraint(name: "Dentist", start: day("2026-06-17"), startTime: "13:00:00", endTime: "17:00:00"),
            ]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacEnabled(true)
            await state.refreshAlmanac(force: true)

            expect(state.goal(forDay: wednesday)?.hours == 4, "half the day off, half the pace, got \(String(describing: state.goal(forDay: wednesday)?.hours))")
            expect(state.timeOffReason(forDay: wednesday) == "Dentist", "and the reason names the appointment")
        }
    }

    await test("the resolved person id survives a restart, so it isn't looked up every launch") {
        try await withTemporaryDirectory { directory in
            let fake = FakeAlmanac()
            fake.knownPeople = [AlmanacPerson(id: "42", email: email)]
            let state = connected(fake, storageDirectory: directory)
            state.setAlmanacEnabled(true)
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
}
