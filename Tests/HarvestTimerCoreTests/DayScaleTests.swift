import Foundation
import Testing

@testable import HarvestTimerCore

@Test("The day timeline's scale")
func runDayScaleTests() {
    let scale = DayScale()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!

    /// A time on 3 August 2026, read in the same zone the scale is given.
    func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2026, month: 8, day: 3, hour: hour, minute: minute
        ))!
    }

    test("the scale covers the working day") {
        expect(scale.startHour == 7 && scale.endHour == 19, "7am to 7pm")
        expect(scale.hourCount == 12, "twelve hours, got \(scale.hourCount)")
    }

    test("a time sits down the column in proportion") {
        expect(scale.position(of: at(7), height: 120, calendar: calendar) == 0, "the first hour is at the top")
        expect(scale.position(of: at(19), height: 120, calendar: calendar) == 120, "the last hour is at the bottom")
        expect(scale.position(of: at(13), height: 120, calendar: calendar) == 60, "midday-ish is halfway")
        expect(scale.position(of: at(7, 30), height: 120, calendar: calendar) == 5, "half an hour is half a step")
    }

    test("times outside the day sit at the near edge") {
        expect(scale.position(of: at(3), height: 120, calendar: calendar) == 0, "before the day starts, pin to the top")
        expect(scale.position(of: at(23), height: 120, calendar: calendar) == 120, "after it ends, pin to the bottom")
    }

    test("hour labels read as a clock does") {
        expect(scale.hourLabel(7) == "7 AM", "morning")
        expect(scale.hourLabel(12) == "12 PM", "noon is 12 PM, not 0 PM")
        expect(scale.hourLabel(13) == "1 PM", "afternoon")
        expect(scale.hourLabel(19) == "7 PM", "evening")
        expect(scale.hourLabel(0) == "12 AM", "midnight is 12 AM, not 0 AM")
    }

    test("quarter labels pad their minutes") {
        expect(scale.quarterLabel(0) == "7:00", "on the hour should read 7:00, not 7:0")
        expect(scale.quarterLabel(1) == "7:15", "a quarter past")
        expect(scale.quarterLabel(2) == "7:30", "half past")
        expect(scale.quarterLabel(3) == "7:45", "a quarter to")
        expect(scale.quarterLabel(4) == "8:00", "the next hour round")
        expect(scale.quarterLabel(20) == "12:00", "noon, five hours in")
        expect(scale.quarterLabel(24) == "1:00", "past noon it reads on a 12-hour clock")
    }

    test("the default zoom fits the hours asked for") {
        expect(scale.zoom(toShow: 3, min: 1, max: 8) == 4, "three visible hours out of twelve is 4x")
        expect(scale.zoom(toShow: 8, min: 1, max: 8) == 1.5, "eight visible hours is 1.5x")
    }

    test("zoom stays between the buttons' limits") {
        expect(scale.zoom(toShow: 1, min: 1, max: 8) == 8, "asking for one hour should stop at the maximum")
        expect(scale.zoom(toShow: 24, min: 1, max: 8) == 1, "asking for more than a day should stop at the minimum")
    }
}
