import Foundation
import Testing

@testable import HarvestTimerCore

@Test("AlmanacAPI")
func runAlmanacAPITests() async {
    await test("resolving people sends a GraphQL query and reads the reply") {
        let server = StubHarvestServer(json: """
        {"data":{"people":[{"id":"1","email":"ada@rolemodelsoftware.com"},{"id":"2","email":"grace@rolemodelsoftware.com"}]}}
        """)
        let api = server.almanacAPI(apiKey: "secret-key")

        let people = try await api.people()

        expect(people.count == 2, "both people came back, got \(people.count)")
        expect(people.first?.email == "ada@rolemodelsoftware.com", "email decoded")

        let request = server.requests[0]
        expect(request.path == "/graphql", "posted to the GraphQL endpoint, got \(request.path)")
        expect(request.method == "POST", "GraphQL is always POST, got \(request.method)")
        expect(
            request.header("Authorization") == "Bearer secret-key",
            "the key travels as a bearer token, got \(String(describing: request.header("Authorization")))"
        )
        expect(
            (request.json["query"] as? String)?.contains("people") == true,
            "the query asks for people, got \(request.json)"
        )
    }

    await test("a person's total pace reads the nested field") {
        let server = StubHarvestServer(json: """
        {"data":{"person":{"totalPace":{"suggestedDailyPace":8.4,"target":450,"worked":120,"remaining":330,"daysIntoReport":15}}}}
        """)
        let api = server.almanacAPI()

        let pace = try await api.totalPace(personId: "1")

        expect(abs(pace.suggestedDailyPace - 8.4) < 0.001, "got \(pace.suggestedDailyPace)")
        expect(pace.target == 450, "got \(pace.target)")

        let request = server.requests[0]
        expect(
            (request.json["query"] as? String)?.contains(#"person(id: "1")"#) == true,
            "the query names the person by id, got \(request.json)"
        )
    }

    await test("a person Almanac doesn't know throws rather than crashing on nil") {
        let server = StubHarvestServer(json: #"{"data":{"person":null}}"#)
        let api = server.almanacAPI()

        var threw = false
        do {
            _ = try await api.totalPace(personId: "999")
        } catch AlmanacAPIError.personNotFound {
            threw = true
        }
        expect(threw, "a missing person should not read as a pace of zero")
    }

    await test("time off comes back from the REST endpoint, snake_case and all") {
        let server = StubHarvestServer(json: """
        [
          {"id":501,"name":"Vacation","start_date":"2026-06-15","end_date":"2026-06-22",
           "start_time":null,"end_time":null,"billable_only":false,"company_wide":false},
          {"id":502,"name":"Doctor","start_date":"2026-07-01","end_date":"2026-07-01",
           "start_time":"13:00:00","end_time":"17:00:00","billable_only":false,"company_wide":false}
        ]
        """)
        let api = server.almanacAPI()

        let constraints = try await api.constraints(email: "ada@rolemodelsoftware.com")

        expect(constraints.count == 2, "both constraints came back, got \(constraints.count)")
        expect(constraints[1].isPartialDay, "the second one has both times set")
        expect(constraints[1].startTime?.hours == 13, "one o'clock, got \(String(describing: constraints[1].startTime?.hours))")

        let request = server.requests[0]
        expect(request.path == "/api/constraints/next_constraints", "hit the constraints endpoint, got \(request.path)")
        expect(
            request.query["email"] == "ada@rolemodelsoftware.com",
            "the email travels as a query param, got \(request.query)"
        )
    }

    await test("a rejected key surfaces as unauthorized") {
        let server = StubHarvestServer([.status(401, body: "")])
        let api = server.almanacAPI()

        var threw = false
        do {
            _ = try await api.people()
        } catch AlmanacAPIError.unauthorized {
            threw = true
        }
        expect(threw, "a 401 should read as the key being rejected")
    }
}
