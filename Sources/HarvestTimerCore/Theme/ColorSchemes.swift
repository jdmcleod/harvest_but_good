import AppKit
import SwiftUI

public extension Palette {
    static let harvest = Palette(
        header: NSColor(hex: 0xF36C00),
        accent: Color(hex: 0xF36C00),
        start: Color(hex: 0x3E8542),
        selection: .accentColor,
        success: .green,
        warning: .yellow,
        danger: .red,
        favorite: .yellow,
        outline: AnyShapeStyle(.quaternary),
        fieldOutline: AnyShapeStyle(.separator),
        breakOutline: Color.secondary.opacity(0.35),
        track: Color.primary.opacity(0.08),
        idleControl: .secondary,
        emphasis: .primary,
        projectColors: [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
    )

    /// Kattsafe's design tokens. The neon ones (magenta, cyan, bright green)
    /// are left out of the project colors: white labels on them won't read.
    static let kattsafe = Palette(
        header: NSColor(hex: 0x1A202C),
        accent: Color(hex: 0x1FA0F6),
        start: Color(hex: 0x25B521),
        selection: Color(hex: 0x5BB2E4),
        success: Color(hex: 0x25B521),
        warning: Color(hex: 0xFF9400),
        danger: Color(hex: 0xFF0000),
        favorite: Color(hex: 0xFFD45D),
        outline: AnyShapeStyle(Color(hex: 0x1FA0F6, opacity: 0.3)),
        fieldOutline: AnyShapeStyle(Color(hex: 0x1FA0F6, opacity: 0.3)),
        breakOutline: Color(hex: 0x5BB2E4, opacity: 0.7),
        track: Color(hex: 0x1FA0F6, opacity: 0.3),
        idleControl: Color(hex: 0x1FA0F6),
        emphasis: Color(hex: 0x5BB2E4),
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
