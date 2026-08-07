import Foundation
import Testing

@testable import HarvestTimerCore

/// What Harvest hands back from a write: the entry on its own, not a page.
private let singleEntry = """
{"id": 1, "spent_date": "2026-08-03", "hours": 1.5, "notes": "wrote it down",
 "is_running": false, "timer_started_at": null,
 "project": {"id": 10, "name": "Project"},
 "task": {"id": 100, "name": "Development"},
 "client": {"id": 1000, "name": "Client"}}
"""

/// Builds a time-entries page holding entries with the given ids.
private func entriesPage(ids: [Int64], nextPage: Int?) -> String {
    let entries = ids.map { id in
        """
        {"id": \(id), "spent_date": "2026-08-03", "hours": 1, "notes": null,
         "is_running": false, "timer_started_at": null,
         "project": {"id": 10, "name": "Project"},
         "task": {"id": 100, "name": "Development"},
         "client": {"id": 1000, "name": "Client"}}
        """
    }
    let next = nextPage.map(String.init) ?? "null"
    return "{\"time_entries\": [\(entries.joined(separator: ","))], \"next_page\": \(next)}"
}

private func assignmentsPage(ids: [Int64], nextPage: Int?) -> String {
    let assignments = ids.map { id in
        """
        {"id": \(id),
         "project": {"id": \(id * 10), "name": "Project \(id)"},
         "client": {"id": 1000, "name": "Client"},
         "task_assignments": [{"task": {"id": 100, "name": "Development"}}]}
        """
    }
    let next = nextPage.map(String.init) ?? "null"
    return "{\"project_assignments\": [\(assignments.joined(separator: ","))], \"next_page\": \(next)}"
}

@Test("Talking to Harvest")
func runHarvestAPITests() async {
    let day = Day(name: "2026-08-03")!

    await test("every request carries the token, the account, and a user agent") {
        let server = StubHarvestServer(json: #"{"id": 7, "first_name": "Ada", "last_name": "Lovelace"}"#)
        let user = try await server.api(token: "secret", accountId: "999").currentUser()

        expect(user.id == 7, "the user should decode")
        expect(user.firstName == "Ada", "snake_case should map to camelCase")
        let sent = server.requests[0]
        expect(sent.path == "/v2/users/me", "wrong path: \(sent.path)")
        expect(sent.method == "GET", "should be a GET, was \(sent.method)")
        expect(sent.header("Authorization") == "Bearer secret", "the token goes in as a bearer")
        expect(sent.header("Harvest-Account-ID") == "999", "Harvest wants the account alongside it")
        expect(sent.header("User-Agent")?.contains("HarvestTimer") == true, "Harvest asks callers to name themselves")
    }

    await test("a rejected token reads as a token problem") {
        let server = StubHarvestServer([.status(401, body: "nope")])
        await expectFailure(from: server) { try await $0.currentUser() } check: { message in
            expect(message.contains("Token not accepted"), "401 should blame the token, said: \(message)")
        }
    }

    await test("403 and 404 read as the wrong account") {
        for status in [403, 404] {
            let server = StubHarvestServer([.status(status)])
            await expectFailure(from: server) { try await $0.currentUser() } check: { message in
                expect(message.contains("Account ID doesn't match"), "\(status) should blame the account, said: \(message)")
            }
        }
    }

    await test("any other status comes back with its code and body") {
        let server = StubHarvestServer([.status(500, body: "Harvest is down")])
        await expectFailure(from: server) { try await $0.currentUser() } check: { message in
            expect(message.contains("500"), "the code should show, said: \(message)")
            expect(message.contains("Harvest is down"), "so should the body, said: \(message)")
        }
    }

    await test("a connection that never lands reads as a network problem") {
        let server = StubHarvestServer([.failure(.notConnectedToInternet)])
        await expectFailure(from: server) { try await $0.currentUser() } check: { message in
            expect(message.hasPrefix("Network error"), "should be named as a network problem, said: \(message)")
        }
    }

    await test("time entries are asked for a page at a time until Harvest stops") {
        let server = StubHarvestServer([
            .json(entriesPage(ids: [1, 2], nextPage: 2)),
            .json(entriesPage(ids: [3], nextPage: 3)),
            .json(entriesPage(ids: [4], nextPage: nil)),
        ])
        let entries = try await server.api().timeEntries(from: day, to: day, userId: 7)

        expect(entries.map(\.id) == [1, 2, 3, 4], "every page should be kept, got \(entries.map(\.id))")
        expect(server.callCount == 3, "should stop once next_page is null, made \(server.callCount) calls")
        expect(server.requests.map { $0.query["page"] } == ["1", "2", "3"], "should follow next_page, not just count up")
        let first = server.requests[0]
        expect(first.query["from"] == "2026-08-03" && first.query["to"] == "2026-08-03", "the range should go in the query")
        expect(first.query["user_id"] == "7", "so should the user")
        expect(first.query["per_page"] == "100", "asking for 100 keeps the round trips down")
    }

    await test("one page of time entries is one call") {
        let server = StubHarvestServer(json: entriesPage(ids: [1], nextPage: nil))
        let entries = try await server.api().timeEntries(from: day, to: day, userId: 7)
        expect(entries.count == 1, "the single page should come back")
        expect(server.callCount == 1, "and should not be asked for again")
    }

    await test("project assignments page the same way") {
        let server = StubHarvestServer([
            .json(assignmentsPage(ids: [1], nextPage: 2)),
            .json(assignmentsPage(ids: [2], nextPage: nil)),
        ])
        let assignments = try await server.api().projectAssignments()

        expect(assignments.map(\.id) == [1, 2], "both pages should be kept, got \(assignments.map(\.id))")
        expect(server.callCount == 2, "should stop at the last page, made \(server.callCount) calls")
        expect(server.requests[0].path == "/v2/users/me/project_assignments", "wrong path")
        expect(assignments[0].taskAssignments.first?.task.name == "Development", "nested tasks should decode")
    }

    await test("the shipped decoder reads Harvest's timestamps") {
        let running = """
        {"time_entries": [{
          "id": 1, "spent_date": "2026-08-03", "hours": 0.25, "notes": null,
          "is_running": true, "timer_started_at": "2026-08-03T14:30:00Z",
          "project": {"id": 10, "name": "Project"},
          "task": {"id": 100, "name": "Development"},
          "client": {"id": 1000, "name": "Client"}
        }], "next_page": null}
        """
        let server = StubHarvestServer(json: running)
        let entry = try await server.api().timeEntries(from: day, to: day, userId: 7)[0]

        expect(entry.isRunning, "is_running should map across")
        expect(entry.spentDate == day, "the spent date should read as a Day")
        // 2026-08-03T14:30:00Z
        let expected = Date(timeIntervalSince1970: 1_785_767_400)
        expect(entry.timerStartedAt == expected, "expected \(expected), got \(String(describing: entry.timerStartedAt))")
    }

    await test("a timestamp the decoder cannot read is a failure, not a wrong date") {
        let bad = """
        {"time_entries": [{
          "id": 1, "spent_date": "2026-08-03", "hours": 0.25, "notes": null,
          "is_running": true, "timer_started_at": "half past two",
          "project": {"id": 10, "name": "Project"},
          "task": {"id": 100, "name": "Development"},
          "client": {"id": 1000, "name": "Client"}
        }], "next_page": null}
        """
        let server = StubHarvestServer(json: bad)
        var threw = false
        do {
            _ = try await server.api().timeEntries(from: day, to: day, userId: 7)
        } catch {
            threw = true
        }
        expect(threw, "an unreadable date should throw rather than pass something wrong along")
    }

    await test("starting a timer sends no hours, so Harvest runs it") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().startTimer(projectId: 10, taskId: 100, spentDate: day, notes: nil)

        let sent = server.requests[0]
        expect(sent.method == "POST", "starting one creates it, was \(sent.method)")
        expect(sent.path == "/v2/time_entries", "wrong path: \(sent.path)")
        expect(sent.header("Content-Type") == "application/json", "a body needs its type")
        expect(sent.json["project_id"] as? Int == 10, "keys should go out in snake_case, got \(sent.json)")
        expect(sent.json["spent_date"] as? String == "2026-08-03", "the date should go as a name")
        expect(sent.json["hours"] == nil, "no hours is what makes Harvest start it running")
        expect(sent.json["notes"] == nil, "nothing was said, so nothing should be sent")
    }

    await test("creating an entry with hours sends them") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().createEntry(
            projectId: 10, taskId: 100, spentDate: day, hours: 1.5, notes: "wrote it down"
        )
        let sent = server.requests[0]
        expect(sent.json["hours"] as? Double == 1.5, "the hours should go, got \(sent.json)")
        expect(sent.json["notes"] as? String == "wrote it down", "so should the notes")
    }

    await test("empty notes are left out rather than sent as nothing") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().createEntry(
            projectId: 10, taskId: 100, spentDate: day, hours: 1, notes: ""
        )
        expect(server.requests[0].json["notes"] == nil, "an empty note should not overwrite anything")
    }

    await test("a change sends only the field it changes") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().updateHours(entryId: 42, hours: 2)

        let sent = server.requests[0]
        expect(sent.method == "PATCH", "a change is a PATCH, was \(sent.method)")
        expect(sent.path == "/v2/time_entries/42", "wrong path: \(sent.path)")
        expect(sent.json.keys.sorted() == ["hours"], "only hours should go, got \(sent.json.keys.sorted())")
    }

    await test("changing the project sends both halves of the booking") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().updateProjectTask(entryId: 42, projectId: 11, taskId: 110)
        let keys = server.requests[0].json.keys.sorted()
        expect(keys == ["project_id", "task_id"], "a project moves with its task, got \(keys)")
    }

    await test("notes are sent even when cleared") {
        let server = StubHarvestServer(json: singleEntry)
        _ = try await server.api().updateNotes(entryId: 42, notes: "")
        let sent = server.requests[0]
        expect(sent.json["notes"] as? String == "", "clearing a note has to be sent to take")
    }

    await test("stopping and restarting hit their own endpoints with no body") {
        let server = StubHarvestServer(json: singleEntry)
        let api = server.api()
        _ = try await api.stop(entryId: 42)
        _ = try await api.restart(entryId: 42)

        expect(server.requests[0].path == "/v2/time_entries/42/stop", "wrong stop path")
        expect(server.requests[1].path == "/v2/time_entries/42/restart", "wrong restart path")
        expect(server.requests.allSatisfy { $0.method == "PATCH" }, "both are PATCHes")
        expect(server.requests.allSatisfy { ($0.body ?? Data()).isEmpty }, "neither sends anything")
    }

    await test("a delete asks for nothing back") {
        let server = StubHarvestServer([.status(200)])
        try await server.api().deleteEntry(entryId: 42)

        let sent = server.requests[0]
        expect(sent.method == "DELETE", "should be a DELETE, was \(sent.method)")
        expect(sent.path == "/v2/time_entries/42", "wrong path: \(sent.path)")
    }

    await test("a delete Harvest refuses still fails") {
        let server = StubHarvestServer([.status(422, body: "locked")])
        var threw = false
        do {
            try await server.api().deleteEntry(entryId: 42)
        } catch {
            threw = true
        }
        expect(threw, "a refused delete should not read as done")
    }
}

/// Runs `call` expecting it to fail, and hands the message to `check`.
private func expectFailure(
    from server: StubHarvestServer,
    _ call: (HarvestAPI) async throws -> Void,
    check: (String) -> Void
) async {
    do {
        try await call(server.api())
        expect(false, "the call should have failed")
    } catch {
        check(error.localizedDescription)
    }
}
