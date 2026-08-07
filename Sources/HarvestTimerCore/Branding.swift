import AppKit
import SwiftUI

public extension Color {
    static let harvest = Color(red: 243 / 255, green: 108 / 255, blue: 0)
}

public extension NSColor {
    static let harvest = NSColor(red: 243 / 255, green: 108 / 255, blue: 0, alpha: 1)
}

public extension Color {
    /// A steady colour per project, so the same project reads the same in the
    /// list, the chips, and the timeline. The palette repeats after eight.
    static func forProject(_ projectId: Int64) -> Color {
        let palette: [Color] = [
            .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown,
        ]
        return palette[Int(projectId % Int64(palette.count))]
    }
}
