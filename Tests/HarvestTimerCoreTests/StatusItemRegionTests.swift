import CoreGraphics
import Testing

@testable import HarvestTimerCore

@Test("Status item click regions")
func runStatusItemRegionTests() {
    test("the leading edge toggles the timer") {
        expect(StatusItemRegion(x: 0) == .timer, "picks the timer")
    }

    test("the middle of the glyph toggles the timer") {
        expect(StatusItemRegion(x: 16) == .timer, "picks the timer")
    }

    test("the glyph's trailing padding still toggles the timer") {
        expect(StatusItemRegion(x: StatusItemRegion.glyphWidth - 0.5) == .timer, "picks the timer")
    }

    test("the first point past the glyph opens the window") {
        expect(StatusItemRegion(x: StatusItemRegion.glyphWidth) == .window, "picks the window")
    }

    test("the running total opens the window") {
        expect(StatusItemRegion(x: 50) == .window, "picks the window")
    }
}
