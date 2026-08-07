import AppKit
import SwiftUI

public extension Color {
    static let harvest = Color(red: 243 / 255, green: 108 / 255, blue: 0)
}

public extension NSColor {
    static let harvest = NSColor(red: 243 / 255, green: 108 / 255, blue: 0, alpha: 1)
}

public extension Color {
    static let projectPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown,
    ]

    /// A steady colour per project, so the same project reads the same in the
    /// list, the chips, and the timeline. The palette repeats after eight.
    static func forProject(_ projectId: Int64) -> Color {
        projectPalette[Int(projectId % Int64(projectPalette.count))]
    }

    static func forFavorite(_ favorite: Favorite) -> Color {
        guard let index = favorite.colorIndex, projectPalette.indices.contains(index) else {
            return forProject(favorite.projectId)
        }
        return projectPalette[index]
    }
}
