import Foundation
import Testing

@testable import HarvestTimerCore

@Test("TimeOfDay")
func runTimeOfDayTests() {
    test("a bare HH:MM:SS parses directly") {
        expect(TimeOfDay(string: "13:00:00")?.hours == 13, "one o'clock")
        expect(TimeOfDay(string: "09:30:00")?.hours == 9.5, "half past nine")
    }

    test("a Rails time column's ISO8601-on-a-dummy-date form parses the same way") {
        // What a `time` column actually serializes to through Rails' JSON
        // encoder — the bug this guards: the bare-HH:MM:SS parser used to
        // silently fail on this and every partial-day constraint read back
        // as having no times at all.
        expect(TimeOfDay(string: "2000-01-01T13:00:00.000Z")?.hours == 13, "got \(String(describing: TimeOfDay(string: "2000-01-01T13:00:00.000Z")?.hours))")
        expect(TimeOfDay(string: "2000-01-01T09:30:00.000Z")?.hours == 9.5, "got \(String(describing: TimeOfDay(string: "2000-01-01T09:30:00.000Z")?.hours))")
    }

    test("a space-separated timestamp parses the same way too") {
        expect(TimeOfDay(string: "2000-01-01 13:00:00")?.hours == 13, "got \(String(describing: TimeOfDay(string: "2000-01-01 13:00:00")?.hours))")
    }

    test("garbage is nil rather than a wrong number") {
        expect(TimeOfDay(string: "") == nil, "empty string")
        expect(TimeOfDay(string: "not a time") == nil, "no digits and colons to find")
        expect(TimeOfDay(string: "13") == nil, "needs at least hours and minutes")
    }

    test("round-tripping through encode gives back the bare HH:MM:SS form") {
        let time = TimeOfDay(string: "2000-01-01T13:05:09.000Z")!
        let data = try! JSONEncoder().encode(time)
        expect(String(decoding: data, as: UTF8.self) == "\"13:05:09\"", "got \(String(decoding: data, as: UTF8.self))")

        let decoded = try! JSONDecoder().decode(TimeOfDay.self, from: data)
        expect(decoded == time, "and decodes back to the same value")
    }
}
