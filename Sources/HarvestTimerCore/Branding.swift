import AppKit
import SwiftUI

public extension Color {
    static let harvest = Color(red: 243 / 255, green: 108 / 255, blue: 0)
}

public extension NSColor {
    static let harvest = NSColor(red: 243 / 255, green: 108 / 255, blue: 0, alpha: 1)
}

public extension Color {
    /// The eight colours projects are dealt from. Favourites choose out of the
    /// same set, so a hand-picked chip still belongs to the palette.
    static let projectPalette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown,
    ]

    /// A steady colour per project, so the same project reads the same in the
    /// list, the chips, and the timeline. The palette repeats after eight.
    static func forProject(_ projectId: Int64) -> Color {
        projectPalette[Int(projectId % Int64(projectPalette.count))]
    }

    /// A favourite's own colour if it has one, and the project's otherwise. An
    /// index outside the palette is treated as no choice at all: a hand-edited
    /// favorites.json should look wrong, not crash.
    static func forFavorite(_ favorite: Favorite) -> Color {
        guard let index = favorite.colorIndex, projectPalette.indices.contains(index) else {
            return forProject(favorite.projectId)
        }
        return projectPalette[index]
    }
}
