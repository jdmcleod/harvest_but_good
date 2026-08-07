import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Decoding Harvest's JSON")
func runDecodingTests() {
    test("time entry page decodes Harvest JSON") {
        let json = """
        {
          "time_entries": [{
            "id": 636709355,
            "spent_date": "2026-08-06",
            "hours": 2.11,
            "notes": "Debugging",
            "is_running": true,
            "timer_started_at": "2026-08-06T14:00:00Z",
            "project": {"id": 14308069, "name": "Online Store"},
            "task": {"id": 8083365, "name": "Programming"},
            "client": {"id": 5735774, "name": "ABC Corp"}
          }],
          "next_page": null
        }
        """
        // The decoder the app ships, not one built for the test: a second
        // decoder here would only prove that the second decoder works.
        let page = try HarvestAPI.decoder.decode(TimeEntriesPage.self, from: Data(json.utf8))
        expect(page.timeEntries.count == 1, "expected 1 entry")
        expect(page.timeEntries.first?.project.name == "Online Store", "project name mismatch")
        expect(page.timeEntries.first?.isRunning == true, "should be running")
        expect(page.timeEntries.first?.timerStartedAt != nil, "timer_started_at should decode")
        expect(page.nextPage == nil, "next_page should be nil")
    }
}
