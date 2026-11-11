import AppKit
import HarvestTimerCore
import SwiftUI

/// The menu bar item. AppKit takes the click, not SwiftUI buttons drawn
/// inside it: on macOS 27 a real click reached those buttons at the wrong
/// point, so the play glyph opened the window. The cursor's own position
/// decides which half was meant.
@MainActor
final class StatusItemController: NSObject, NSViewToolTipOwner {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let onOpenWindow: () -> Void

    init(state: AppState, onOpenWindow: @escaping () -> Void) {
        self.state = state
        self.onOpenWindow = onOpenWindow
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(clicked(_:))
        embedWidget(in: button)
        button.addToolTip(
            NSRect(x: 0, y: 0, width: StatusItemRegion.glyphWidth, height: 100),
            owner: self, userData: nil
        )
        button.addToolTip(
            NSRect(x: StatusItemRegion.glyphWidth, y: 0, width: 10_000, height: 100),
            owner: self, userData: nil
        )
    }

    /// The window holding the item, which sits on the display whose menu bar
    /// took the click.
    var buttonWindow: NSWindow? { statusItem.button?.window }

    private func embedWidget(in button: NSStatusBarButton) {
        let hosting = ClickThroughHostingView(rootView: StatusWidget().environment(state))
        hosting.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: button.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ])
    }

    @objc private func clicked(_ button: NSStatusBarButton) {
        switch region(of: button) {
        case .timer: Task { await state.toggleCurrentTimer() }
        case .window: onOpenWindow()
        }
    }

    private func region(of button: NSStatusBarButton) -> StatusItemRegion {
        guard let window = button.window else { return .window }
        let inWindow = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        return StatusItemRegion(x: button.convert(inWindow, from: nil).x)
    }

    nonisolated func view(
        _ view: NSView,
        stringForToolTip tag: NSView.ToolTipTag,
        point: NSPoint,
        userData data: UnsafeMutableRawPointer?
    ) -> String {
        MainActor.assumeIsolated {
            switch StatusItemRegion(x: point.x) {
            case .timer: timerHelp
            case .window: "Open HarvestButGood"
            }
        }
    }

    private var timerHelp: String {
        let action = state.runningEntry == nil ? "Resume most recent timer" : "Stop timer"
        guard let progress = state.todayGoalProgress else { return action }
        if progress.isMet {
            return "\(action)\nPace of \(Hours.formatted(progress.goalHours)) met"
        }
        let left = Hours.formatted(progress.remainingHours)
        return "\(action)\n\(left) left of \(Hours.formatted(progress.goalHours))"
    }
}

/// Draws only. Clicks fall through to the status bar button underneath.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
