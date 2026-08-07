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
        expect(Hours.parse("1:75") == nil, "minutes over 59 should not parse")
        expect(Hours.parse("-1") == nil, "negative should not parse")
        expect(Hours.parse("25") == nil, "over 24 hours should not parse")
        expect(Hours.parse(":30") == 0.5, "leading colon means minutes only")
        expect(Hours.parse(":90") == nil, "minutes over 59 still should not parse")
        expect(Hours.parse(":") == nil, "a bare colon should not parse")
    }

    test("writes hours as h:mm") {
        expect(Hours.formatted(0) == "0:00", "nothing should read as 0:00")
        expect(Hours.formatted(1.5) == "1:30", "1.5 should read as 1:30")
        expect(Hours.formatted(0.75) == "0:45", "under an hour still shows a leading 0")
        expect(Hours.formatted(0.25) == "0:15", "a quarter hour should pad its minutes")
        expect(Hours.formatted(10) == "10:00", "two-digit hours should not pad")
        expect(Hours.formatted(24) == "24:00", "a full day should read as 24:00")
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
