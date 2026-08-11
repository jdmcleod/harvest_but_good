import AppKit
import SwiftUI

/// A way back to the week today falls in, for when the header chevrons have
/// taken you somewhere else.
public struct ThisWeekButton: View {
    @Environment(AppState.self) private var state

    public init() {}

    /// The slot keeps its size whether or not the button is in it: an accessory
    /// that ever measures zero is one AppKit leaves collapsed for good.
    ///
    /// Public because a titlebar accessory takes its width from the hosting
    /// view's frame rather than from what SwiftUI asks for, so whoever hosts
    /// this has to set the same size by hand.
    public static let slot = CGSize(width: 30, height: 24)

    /// `calendar.badge` arrived with SF Symbols 7, and the app still runs on
    /// macOS 14, where asking for it by name draws nothing at all. Fall back
    /// to a plain calendar there rather than leave an empty button behind.
    private static let symbol: String = {
        let preferred = "calendar.badge"
        let available = NSImage(systemSymbolName: preferred, accessibilityDescription: nil) != nil
        return available ? preferred : "calendar"
    }()

    public var body: some View {
        ZStack {
            if !state.isViewingCurrentWeek {
                Button {
                    state.goToToday()
                } label: {
                    Image(systemName: Self.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingCursor()
                .foregroundStyle(.white)
                .help("Back to this week")
            }
        }
        .frame(width: Self.slot.width, height: Self.slot.height)
    }
}
