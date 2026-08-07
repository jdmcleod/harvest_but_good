import Foundation
import HarvestTimerCore

func runDayTests() {
    test("a day names the date it falls on") {
        let noon = Calendar.current.date(
            from: DateComponents(year: 2025, month: 8, day: 6, hour: 12)
        )!
        expect(Day(noon).name == "2025-08-06", "expected 2025-08-06, got \(Day(noon).name)")
        expect(Day(noon) == day("2025-08-06"), "the two ways of building a day should agree")
    }

    test("a day round-trips through its own name") {
        let original = day("2025-08-06")
        expect(Day(original.date!) == original, "date and back should be the same day")
    }

    test("only real dates make a day") {
        expect(Day(name: "not a date") == nil, "letters should not parse")
        expect(Day(name: "2025-13-45") == nil, "an impossible date should not parse")
        expect(Day(name: "2025-08-06") != nil, "a real date should parse")
    }

    test("days sort and compare by date") {
        expect(day("2025-08-05") < day("2025-08-06"), "earlier should sort first")
        expect(day("2025-12-31") < day("2026-01-01"), "sorting should cross a year")
        let sorted = [day("2025-08-07"), day("2025-08-05"), day("2025-08-06")].sorted()
        expect(sorted.map(\.name) == ["2025-08-05", "2025-08-06", "2025-08-07"], "wrong order")
    }

    test("a day encodes as the bare string Harvest uses") {
        let encoded = try JSONEncoder().encode(day("2025-08-06"))
        expect(String(data: encoded, encoding: .utf8) == "\"2025-08-06\"", "should encode as a string")
        let decoded = try JSONDecoder().decode(Day.self, from: encoded)
        expect(decoded == day("2025-08-06"), "should decode back")
    }

    test("decoding rejects a day that is not a date") {
        do {
            _ = try JSONDecoder().decode(Day.self, from: Data("\"tomorrow\"".utf8))
            expect(false, "decoding nonsense should throw")
        } catch {
            expect(true, "decoding nonsense throws")
        }
    }
}
