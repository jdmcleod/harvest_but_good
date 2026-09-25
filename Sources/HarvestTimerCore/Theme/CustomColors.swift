import AppKit
import SwiftUI

/// The colors someone can pick for themselves in place of Harvest's. Outlines,
/// the goal bar's track and idle play buttons follow the accent, and the
/// break edge follows the highlight, so four picks restyle the whole window.
/// Picks survive switching the feature off, so turning it back on returns to
/// them rather than to the defaults.
public struct CustomColors: Codable, Equatable, Sendable {
    public var isEnabled = false
    public var header: UInt32 = 0x1A202C
    public var accent: UInt32 = 0x1FA0F6
    public var start: UInt32 = 0x25B521
    /// A picked entry, a picked timeline block, and a break's dashed edge.
    public var highlight: UInt32 = 0x5BB2E4

    public static let defaults = CustomColors()

    public init() {}

    public var palette: Palette {
        guard isEnabled else { return .harvest }
        return Palette(
            header: NSColor(hex: header),
            accent: Color(hex: accent),
            start: Color(hex: start),
            selection: Color(hex: highlight),
            success: Color(hex: 0x25B521),
            warning: Color(hex: 0xFF9400),
            danger: Color(hex: 0xFF0000),
            favorite: Color(hex: 0xFFD45D),
            outline: AnyShapeStyle(Color(hex: accent, opacity: 0.3)),
            fieldOutline: AnyShapeStyle(Color(hex: accent, opacity: 0.3)),
            breakOutline: Color(hex: highlight, opacity: 0.7),
            track: Color(hex: accent, opacity: 0.3),
            idleControl: Color(hex: accent),
            emphasis: Color(hex: highlight),
            // Neon picks are left out: white labels on them won't read.
            projectColors: [
                Color(hex: 0x1C2FD6),
                Color(hex: 0x25B521),
                Color(hex: 0xEF6C00),
                Color(hex: 0x9900FF),
                Color(hex: 0xFD561F),
                Color(hex: 0x5BB2E4),
                Color(hex: 0x136010),
                Color(hex: 0xFF9400),
            ]
        )
    }

    public var usesDefaultColors: Bool {
        var colors = self
        colors.isEnabled = Self.defaults.isEnabled
        return colors == Self.defaults
    }

    public mutating func resetColors() {
        let isEnabled = isEnabled
        self = Self.defaults
        self.isEnabled = isEnabled
    }

    public static func hex(of color: Color) -> UInt32 {
        NSColor(color).hex
    }
}
