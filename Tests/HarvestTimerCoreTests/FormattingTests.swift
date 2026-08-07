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
}
