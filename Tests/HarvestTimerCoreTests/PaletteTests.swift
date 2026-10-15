import AppKit
import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Palette")
func runPaletteTests() {
    test("project colors wrap once they run out") {
        let palette = Palette.harvest
        let count = Int64(palette.projectColors.count)
        expect(palette.forProject(1) == palette.forProject(1 + count), "same slot after a full lap")
    }

    test("hex survives a round trip through a color") {
        for hex: UInt32 in [0xF36C00, 0x3E8542, 0x000000, 0xFFFFFF, 0x1FA0F6] {
            expect(NSColor(hex: hex).hex == hex, "\(String(hex, radix: 16))")
        }
    }
}

@Test("CustomColors")
func runCustomColorsTests() {
    test("switched off, the app wears Harvest's colors") {
        var colors = CustomColors()
        colors.header = 0x123456
        expect(colors.palette.header.hex == Palette.harvest.header.hex, "harvest header while off")
        colors.isEnabled = true
        expect(colors.palette.header.hex == 0x123456, "picked header once on")
    }

    test("each pick reaches every color that follows it") {
        var colors = CustomColors()
        colors.isEnabled = true
        colors.header = 0x111111
        colors.accent = 0x222222
        colors.start = 0x333333
        colors.highlight = 0x444444
        let palette = colors.palette
        let hex = CustomColors.hex(of:)
        expect(palette.header.hex == 0x111111, "header")
        expect(hex(palette.accent) == 0x222222, "accent")
        expect(hex(palette.track) == 0x222222, "track follows accent")
        expect(hex(palette.idleControl) == 0x222222, "idle control follows accent")
        expect(hex(palette.start) == 0x333333, "start")
        expect(hex(palette.selection) == 0x444444, "selection follows highlight")
        expect(hex(palette.emphasis) == 0x444444, "emphasis follows highlight")
        expect(hex(palette.breakOutline) == 0x444444, "break edge follows highlight")
        expect(hex(palette.breakFill) == 0x444444, "break fill follows highlight")
    }

    test("a save from before a pick existed keeps the picks it has") {
        let data = Data(#"{"isEnabled":true,"accent":1193046}"#.utf8)
        let loaded = try JSONDecoder().decode(CustomColors.self, from: data)
        expect(loaded.isEnabled, "still on")
        expect(loaded.accent == 0x123456, "accent kept")
        expect(loaded.header == CustomColors.defaults.header, "missing header takes the default")
        expect(loaded.highlight == CustomColors.defaults.highlight, "missing highlight takes the default")
    }

    test("the project color count matches Harvest's") {
        // A favorite's chosen color is saved as an index, so switching must
        // land it on the same slot rather than off the end.
        var colors = CustomColors()
        colors.isEnabled = true
        expect(
            colors.palette.projectColors.count == Palette.harvest.projectColors.count,
            "\(colors.palette.projectColors.count) against \(Palette.harvest.projectColors.count)"
        )
    }

    test("reset puts the colors back but leaves the switch") {
        var colors = CustomColors()
        colors.isEnabled = true
        colors.accent = 0x123456
        colors.highlight = 0x654321
        expect(!colors.usesDefaultColors, "picks count as changed")
        colors.resetColors()
        expect(colors.usesDefaultColors, "back to defaults")
        expect(colors.isEnabled, "still on")
    }

    test("survives being saved and loaded") {
        var colors = CustomColors()
        colors.isEnabled = true
        colors.start = 0x123456
        let data = try JSONEncoder().encode(colors)
        let loaded = try JSONDecoder().decode(CustomColors.self, from: data)
        expect(loaded == colors, "same after a round trip")
    }
}
