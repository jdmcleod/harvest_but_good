import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Palette")
func runPaletteTests() {
    test("every scheme has as many project colors as the others") {
        // A favorite's chosen color is saved as an index, so switching scheme
        // must land it on the same slot rather than off the end.
        let counts = Set(ColorTheme.allCases.map { $0.palette.projectColors.count })
        expect(counts.count == 1, "project color counts differ: \(counts)")
    }

    test("the saved theme names stay put") {
        expect(ColorTheme(rawValue: "harvest") == .harvest, "harvest")
        expect(ColorTheme(rawValue: "kattsafe") == .kattsafe, "kattsafe")
    }

    test("project colors wrap once they run out") {
        let palette = Palette.kattsafe
        let count = Int64(palette.projectColors.count)
        expect(palette.forProject(1) == palette.forProject(1 + count), "same slot after a full lap")
    }
}
