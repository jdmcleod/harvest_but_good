import Foundation
import HarvestTimerCore

func runWeekCalendarTests() {
    let week = WeekCalendar()
    let calendar = Calendar.current

    func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    func weekNames(_ date: Date) -> [String] {
        week.week(containing: date).map { Day($0).name }
    }

    // 4 August 2025 is a Monday, 10 August the Sunday after it.
    let firstWeek = ["2025-08-04", "2025-08-05", "2025-08-06", "2025-08-07", "2025-08-08"]

    test("the week is Monday to Friday") {
        expect(weekNames(date(2025, 8, 6)) == firstWeek, "got \(weekNames(date(2025, 8, 6)))")
    }

    test("every weekday of a week gives the same week") {
        for day in 4...8 {
            expect(weekNames(date(2025, 8, day)) == firstWeek, "day \(day) gave a different week")
        }
    }

    test("a weekend belongs to the week that just finished") {
        expect(weekNames(date(2025, 8, 9)) == firstWeek, "Saturday should look back")
        expect(weekNames(date(2025, 8, 10)) == firstWeek, "Sunday should look back")
    }

    test("the week starts at midnight, not the time of day") {
        let afternoon = calendar.date(
            from: DateComponents(year: 2025, month: 8, day: 6, hour: 16, minute: 30)
        )!
        expect(week.week(containing: afternoon).first == date(2025, 8, 4), "should be Monday midnight")
    }

    test("a week can span the end of a month") {
        expect(
            weekNames(date(2025, 9, 3)) == ["2025-09-01", "2025-09-02", "2025-09-03", "2025-09-04", "2025-09-05"],
            "got \(weekNames(date(2025, 9, 3)))"
        )
        // 1 January 2026 is a Thursday, so its week starts in December.
        expect(weekNames(date(2026, 1, 1)).first == "2025-12-29", "the week should reach back a year")
    }

    test("days lists both ends of the range") {
        let days = week.days(from: Day(name: "2025-08-04")!, to: Day(name: "2025-08-08")!)
        expect(days.map(\.name) == firstWeek, "got \(days.map(\.name))")
    }

    test("a single-day range is that day") {
        let days = week.days(from: Day(name: "2025-08-04")!, to: Day(name: "2025-08-04")!)
        expect(days.map(\.name) == ["2025-08-04"], "got \(days.map(\.name))")
    }

    test("a backwards range is empty") {
        expect(week.days(from: Day(name: "2025-08-08")!, to: Day(name: "2025-08-04")!).isEmpty,
               "to before from should give nothing")
    }

    test("a range can cross a month and a year") {
        let days = week.days(from: Day(name: "2025-12-30")!, to: Day(name: "2026-01-02")!)
        expect(
            days.map(\.name) == ["2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02"],
            "got \(days.map(\.name))"
        )
    }
}
