import AppKit
import HarvestTimerCore
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var state: AppState!
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var hasRestoredFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.buildMainMenu()
        state = AppState()
        state.start()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let hosting = NSHostingView(
            rootView: StatusWidget(openWindow: { [weak self] in self?.toggleWindow() })
                .environment(state)
        )
        hosting.translatesAutoresizingMaskIntoConstraints = false
        if let button = statusItem.button {
            button.addSubview(hosting)
            NSLayoutConstraint.activate([
                hosting.topAnchor.constraint(equalTo: button.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: button.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: button.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            ])
        }

        let rootHosting = NSHostingController(rootView: RootView().environment(state))
        window = NSWindow(contentViewController: rootHosting)
        window.title = "HarvestButGood"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .harvest
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.addTitlebarAccessoryViewController(makeTodayAccessory())
        hasRestoredFrame = window.setFrameUsingName("HarvestTimerMain")
        window.setFrameAutosaveName("HarvestTimerMain")

        state.onAFKDetected = { [weak self] in self?.showWindow() }
        showWindow()
    }

    /// The back-to-today button. A titlebar accessory rather than part of
    /// `WeekHeader` because the titlebar holds nothing else, so the button
    /// costs the header no room, and AppKit lays it out clear of the window
    /// buttons on its own.
    private func makeTodayAccessory() -> NSTitlebarAccessoryViewController {
        let hosting = NSHostingView(rootView: TodayButton().environment(state))
        // The titlebar reads the width off this frame, and leaves an accessory
        // it measures at zero collapsed for good. Auto layout does not get a
        // say here, so the size is set outright.
        hosting.frame = NSRect(origin: .zero, size: TodayButton.slot)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = hosting
        accessory.layoutAttribute = .leading
        return accessory
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }

    private func toggleWindow() {
        if window.isVisible, window.isKeyWindow, isOnClickedScreen {
            window.orderOut(nil)
            return
        }
        Task { await state.sync() }
        // A click on another display's menu bar means the user wants the
        // window there, not wherever it was last left.
        if !isOnClickedScreen { hasRestoredFrame = false }
        showWindow()
    }

    /// The status item's window lives on whichever display's menu bar took
    /// the click, so its screen is the one the user is looking at.
    private var isOnClickedScreen: Bool {
        guard let clicked = statusItem.button?.window?.screen else { return true }
        return window.screen == clicked
    }

    private func showWindow() {
        state.windowDidOpen()
        if !hasRestoredFrame {
            positionUnderStatusItem()
            hasRestoredFrame = true
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func buildMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About HarvestButGood",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide HarvestButGood",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h"
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit HarvestButGood",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        main.addItem(submenu: appMenu, title: "HarvestButGood")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(
            withTitle: "Close Window",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        main.addItem(submenu: fileMenu, title: "File")

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All",
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        )
        main.addItem(submenu: editMenu, title: "Edit")

        return main
    }

    private func positionUnderStatusItem() {
        guard let buttonWindow = statusItem.button?.window else {
            window.center()
            return
        }
        let anchor = buttonWindow.frame
        let x = min(
            anchor.midX - window.frame.width / 2,
            (buttonWindow.screen?.visibleFrame.maxX ?? anchor.maxX) - window.frame.width - 8
        )
        window.setFrameTopLeftPoint(NSPoint(x: max(x, 8), y: anchor.minY - 6))
    }
}

private extension NSMenu {
    func addItem(submenu: NSMenu, title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        addItem(item)
    }
}

private struct StatusWidget: View {
    @Environment(AppState.self) private var state
    let openWindow: () -> Void

    private var isRunning: Bool { state.runningEntry != nil }

    /// The play/pause control, with today's progress standing in for the
    /// circle the glyph would otherwise draw around itself. One circle rather
    /// than two, so the indicator costs the menu bar no room at all.
    ///
    /// The track matters as much as the arc: an hour into an eight hour day the
    /// arc alone is a stray tick, and the glyph loses the outline that made it
    /// read as a button.
    @ViewBuilder private var glyph: some View {
        if let progress = state.todayGoalProgress {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.25), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(
                        progress.isMet ? Color.harvestGreen : accent,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                Image(systemName: isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.primary)
            }
            .padding(1)
            .help(goalHelp(progress))
        } else {
            Group {
                if isRunning {
                    Image(systemName: "pause.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, Color.harvest)
                } else {
                    Image(systemName: "play.circle")
                        .foregroundStyle(Color.primary)
                }
            }
            .font(.system(size: 15, weight: .medium))
        }
    }

    /// Orange is the running colour throughout the app, so the ring earns it
    /// only while the clock is going. A stopped timer keeps the ring neutral,
    /// where it reads as chrome rather than as something happening.
    ///
    /// `.primary` rather than white: nothing tints the menu bar behind this, so
    /// a fixed white would vanish on a light one.
    private var accent: Color { isRunning ? .harvest : .primary }

    private func goalHelp(_ progress: GoalProgress) -> String {
        if progress.isMet {
            return "Goal of \(Hours.formatted(progress.goalHours)) met"
        }
        return "\(Hours.formatted(progress.remainingHours)) left of \(Hours.formatted(progress.goalHours))"
    }

    var body: some View {
        // Each button pads itself so the whole strip is clickable, not just
        // the glyph and the digits.
        HStack(spacing: 0) {
            Button {
                Task { await state.toggleCurrentTimer() }
            } label: {
                glyph
                .frame(width: 16, height: 16)
                .padding(.leading, 8)
                .padding(.trailing, 3)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isRunning ? "Stop timer" : "Resume most recent timer")

            Button(action: openWindow) {
                Text(state.menuBarTitle)
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(isRunning ? Color.white : Color.primary)
                    .padding(.leading, 3)
                    .padding(.trailing, 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open HarvestButGood")
        }
        .frame(maxHeight: .infinity)
        .fixedSize(horizontal: true, vertical: false)
    }
}
