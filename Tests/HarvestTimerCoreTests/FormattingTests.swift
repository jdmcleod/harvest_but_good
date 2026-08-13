import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Formatting")
func runFormattingTests() {
    test("parses durations in h:mm and decimal formats") {
        expect(Hours.parse("1:30") == 1.5, "1:30 should parse to 1.5")
        expect(Hours.parse("0:45") == 0.75, "0:45 should parse to 0.75")
        expect(Hours.parse(" 2.25 ") == 2.25, "decimal with whitespace should parse")
        expect(Hours.parse("0") == 0, "zero should parse")
        expect(Hours.parse("24:00") == 24, "24:00 should parse")
        expect(Hours.parse("abc") == nil, "letters should not parse")
        expect(Hours.parse("-1") == nil, "negative should not parse")
        expect(Hours.parse("25:00") == nil, "over 24 hours should not parse")
        expect(Hours.parse(":30") == 0.5, "leading colon means minutes only")
        expect(Hours.parse(":") == nil, "a bare colon should not parse")
    }

    test("bare digits fill in from the right as h:mm") {
        expect(Hours.parse("5") == 5.0 / 60, "a lone digit is minutes")
        expect(Hours.parse("45") == 0.75, "two digits are minutes")
        expect(Hours.parse("069") == 1.15, "069 should be an hour and nine")
        expect(Hours.parse("69") == 1.15, "the leading zero should not matter")
        expect(Hours.parse("90") == 1.5, "90 minutes should roll over into 1:30")
        expect(Hours.parse("130") == 1.5, "130 should be one hour thirty, not 130 minutes")
        expect(Hours.parse("230") == 2.5, "230 should be two hours thirty")
        expect(Hours.parse("1300") == 13, "four digits should read as 13:00")
        expect(Hours.parse("2500") == nil, "digit-filled hours over a day should not parse")
        expect(Hours.parse("12 34") == nil, "a space in the middle should not parse")
    }

    test("a decimal point is what marks a value as hours") {
        expect(Hours.parse("8") == 8.0 / 60, "a bare 8 is eight minutes")
        expect(Hours.parse("8.0") == 8, "8.0 is eight hours")
        expect(Hours.parse("2.5") == 2.5, "2.5 is two and a half hours")
        expect(Hours.parse(".5") == 0.5, "a leading point still reads as hours")
        expect(Hours.parse("1.2.3") == nil, "two points should not parse")
    }

    test("minutes roll over past 59 in the h:mm form too") {
        expect(Hours.parse("1:75") == 2.25, "1:75 should carry into 2:15")
        expect(Hours.parse(":90") == 1.5, ":90 should carry into 1:30")
    }

    test("a leading sign adjusts the value already there") {
        expect(Hours.parse("+15", relativeTo: 1) == 1.25, "+15 should add a quarter hour")
        expect(Hours.parse("-15", relativeTo: 1) == 0.75, "-15 should take one off")
        expect(Hours.parse("+1:30", relativeTo: 1) == 2.5, "h:mm should work after a sign")
        expect(Hours.parse("+130", relativeTo: 1) == 2.5, "digits fill from the right after a sign too")
        expect(Hours.parse("+0.5", relativeTo: 1) == 1.5, "a decimal after a sign is hours")
        expect(Hours.parse("+ 15", relativeTo: 1) == 1.25, "a space after the sign should be allowed")
        expect(Hours.parse("15", relativeTo: 1) == 0.25, "without a sign it replaces rather than adds")
        expect(Hours.parse("+", relativeTo: 1) == nil, "a lone sign should not parse")
        expect(Hours.parse("+abc", relativeTo: 1) == nil, "letters after a sign should not parse")
    }

    // The Move sheet reads its amount with the plain parse, and an amount to
    // move is never an adjustment. Its immunity should be stated, not assumed.
    test("the plain parse refuses an adjustment") {
        expect(Hours.parse("+15") == nil, "a leading plus should not parse")
        expect(Hours.parse("-15") == nil, "a leading minus should not parse")
    }

    test("an adjustment that runs off either end is refused") {
        expect(Hours.parse("-90", relativeTo: 0.5) == nil, "subtracting past zero should not parse")
        expect(Hours.parse("-30", relativeTo: 0.5) == 0, "landing exactly on zero is fine")
        expect(Hours.parse("+2:00", relativeTo: 23) == nil, "adding past a day should not parse")
        expect(Hours.parse("+1:00", relativeTo: 23) == 24, "landing exactly on a day is fine")
    }

    test("writes hours as h:mm") {
        expect(Hours.formatted(0) == "0:00", "nothing should read as 0:00")
        expect(Hours.formatted(1.5) == "1:30", "1.5 should read as 1:30")
        expect(Hours.formatted(0.75) == "0:45", "under an hour still shows a leading 0")
        expect(Hours.formatted(0.25) == "0:15", "a quarter hour should pad its minutes")
        expect(Hours.formatted(10) == "10:00", "two-digit hours should not pad")
        expect(Hours.formatted(24) == "24:00", "a full day should read as 24:00")
    }

    test("rounding to the minute matches what gets written") {
        // The duration editor seeds its field from this, so a value that has
        // been through it has to survive being written and read back exactly.
        for seconds in stride(from: 0, through: 3600, by: 7) {
            let hours = Double(seconds) / 3600
            let rounded = Hours.toNearestMinute(hours)
            expect(
                Hours.parse(Hours.formatted(rounded)) == rounded,
                "\(Hours.formatted(rounded)) should read back as the number it was written from"
            )
        }
        expect(Hours.toNearestMinute(1 + 1.0 / 180) == 1, "20 seconds should round down")
        expect(Hours.toNearestMinute(1 + 1.0 / 120) == 1 + 1.0 / 60, "30 seconds should round up")
    }

    test("writing hours rounds to the nearest minute") {
        // 1/60 of an hour is a minute, so a third of that is 20 seconds.
        expect(Hours.formatted(1 + 1.0 / 180) == "1:00", "20 seconds should round down")
        expect(Hours.formatted(1 + 1.0 / 120) == "1:01", "30 seconds should round up")
        expect(Hours.formatted(0.9999) == "1:00", "a shade under an hour should carry")
    }

    test("writing hours and reading them back gives the same number") {
        for minutes in stride(from: 0, through: 24 * 60, by: 7) {
            let hours = Double(minutes) / 60
            let text = Hours.formatted(hours)
            guard let read = Hours.parse(text) else {
                expect(false, "\(text) should parse back")
                continue
            }
            expect(abs(read - hours) < 1e-9, "\(text) should read back as \(hours), got \(read)")
        }
    }

    test("writes a span in words") {
        expect(Hours.inWords(seconds: 30) == "less than a minute", "under a minute")
        expect(Hours.inWords(seconds: 60) == "1 min", "one minute")
        expect(Hours.inWords(seconds: 45 * 60) == "45 min", "under an hour")
        expect(Hours.inWords(seconds: 3600) == "1 hour", "an hour is singular")
        expect(Hours.inWords(seconds: 2 * 3600) == "2 hours", "more than one is plural")
        expect(Hours.inWords(seconds: 3600 + 12 * 60) == "1 hr 12 min", "hours and minutes together")
        expect(Hours.inWords(seconds: 0) == "less than a minute", "nothing at all")
        expect(Hours.inWords(seconds: -60) == "less than a minute", "a span that ran backwards")
    }
}
