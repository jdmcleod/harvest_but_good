import AppKit
import SwiftUI

public extension View {
    func pointingCursor(_ enabled: Bool = true) -> some View {
        modifier(PointingCursorModifier(enabled: enabled))
    }
}

private struct PointingCursorModifier: ViewModifier {
    let enabled: Bool
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside && enabled && !pushed {
                    NSCursor.pointingHand.push()
                    pushed = true
                } else if !inside && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onChange(of: enabled) { _, stillEnabled in
                if !stillEnabled && pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}
