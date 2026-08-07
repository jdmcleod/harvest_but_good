import Foundation
import HarvestTimerCore

func runFormattingTests() {
    test("parses durations in h:mm and decimal formats") {
        expect(parseHours("1:30") == 1.5, "1:30 should parse to 1.5")
        expect(parseHours("0:45") == 0.75, "0:45 should parse to 0.75")
        expect(parseHours(" 2.25 ") == 2.25, "decimal with whitespace should parse")
        expect(parseHours("0") == 0, "zero should parse")
        expect(parseHours("24:00") == 24, "24:00 should parse")
        expect(parseHours("abc") == nil, "letters should not parse")
        expect(parseHours("1:75") == nil, "minutes over 59 should not parse")
        expect(parseHours("-1") == nil, "negative should not parse")
        expect(parseHours("25") == nil, "over 24 hours should not parse")
        expect(parseHours(":30") == 0.5, "leading colon means minutes only")
        expect(parseHours(":90") == nil, "minutes over 59 still should not parse")
        expect(parseHours(":") == nil, "a bare colon should not parse")
    }
}
