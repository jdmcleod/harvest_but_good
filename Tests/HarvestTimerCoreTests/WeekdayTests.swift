import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Weekdays")
func runWeekdayTests() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    func date(_ name: String) -> Date {
        var components = DateComponents()
        components.timeZone = calendar.timeZone
        let parts = name.split(separator: "-").map { Int($0)! }
        (components.year, components.month, components.day) = (parts[0], parts[1], parts[2])
        return calendar.date(from: components)!
    }

    test("a date lands on its weekday, Sunday's Gregorian 1 included") {
        expect(Weekday(date("2025-08-04"), calendar: calendar) == .monday, "4 August 2025 was a Monday")
        expect(Weekday(date("2025-08-06"), calendar: calendar) == .wednesday, "6 August 2025 was a Wednesday")
        expect(Weekday(date("2025-08-09"), calendar: calendar) == .saturday, "9 August 2025 was a Saturday")
        expect(Weekday(date("2025-08-10"), calendar: calendar) == .sunday, "10 August 2025 was a Sunday")
    }

    test("the working week is Monday through Friday, in order") {
        expect(
            Weekday.workdays == [.monday, .tuesday, .wednesday, .thursday, .friday],
            "five days, as the week header shows them"
        )
    }

    test("labels are short enough for a tab") {
        expect(Weekday.wednesday.shortName == "Wed", "got \(Weekday.wednesday.shortName)")
        expect(Weekday.wednesday.name == "Wednesday", "got \(Weekday.wednesday.name)")
    }

    test("goals keyed by weekday encode as a readable object") {
        let settings = GoalSettings(
            days: [.monday: DayGoal(hours: 8, breakHours: 0.5)],
            breakSkippedOn: day("2025-08-06")
        )
        let data = try JSONEncoder().encode(settings)
        let text = String(decoding: data, as: UTF8.self)
        expect(text.contains("\"monday\""), "the weekday is its own key, got \(text)")
        expect(text.contains("\"2025-08-06\""), "the skipped day is a plain date string, got \(text)")

        let decoded = try JSONDecoder().decode(GoalSettings.self, from: data)
        expect(decoded == settings, "the settings survive the round trip")
    }
}
