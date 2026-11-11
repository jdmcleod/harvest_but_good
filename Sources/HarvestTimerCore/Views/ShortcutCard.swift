import Carbon.HIToolbox
import SwiftUI

/// The global shortcut that shows the window from anywhere and, pressed
/// again, hides it and hands focus back to the app you came from. The
/// window's own keys are set in the shortcut list.
struct ShortcutCard: View {
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands

    var body: some View {
        SettingsCard(title: "Keyboard Shortcut", systemImage: "keyboard") {
            ShowHideRecorder()
        } content: {
            Text("Show or hide the window from any app. Hiding it this way puts you back where you were.")
                .foregroundStyle(.secondary)
            Button("Other shortcuts…") {
                commands.showingSettings = false
                commands.showingShortcuts = true
            }
            .buttonStyle(.link)
        }
    }
}

struct ShowHideRecorder: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ShortcutRecorder(key: state.hotKey, allowsBareKey: false) { key in
            // Tried before it is kept, so a combination another app owns
            // never replaces one that works.
            guard HotKeyCenter.shared.register(key) else { return "\(key.display) is taken by another app" }
            state.hotKey = key
            return nil
        }
    }
}

/// A button that shows a shortcut and, clicked, records the next press as
/// its new one. `pick` returns why a press can't be used, or nil once it has
/// been kept.
struct ShortcutRecorder: View {
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands
    @Environment(\.palette) private var palette
    let key: HotKey?
    var allowsBareKey = true
    let pick: (HotKey) -> String?
    var clear: (() -> Void)?
    @State private var recording = false
    @State private var hovering = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 2) {
                if hovering, !recording, key != nil, let clear {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove the shortcut")
                }
                recordButton
            }
            .onHover { hovering = $0 }

            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private var recordButton: some View {
            Button {
                recording ? stop() : start()
            } label: {
                HStack(spacing: 3) {
                    if recording {
                        Text("Press keys…")
                    } else if let key {
                        ForEach(Array(key.displayParts.enumerated()), id: \.offset) { _, part in Keycap(part) }
                    } else {
                        Text(hovering ? "Set" : "—")
                            .foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: 11.5, weight: .semibold))
                .padding(.horizontal, 4)
                .frame(minHeight: 23)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(recording ? palette.accent.opacity(0.15) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            recording ? palette.accent : Color.primary.opacity(hovering ? 0.15 : 0)
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the keys. Esc cancels.")
    }

    private func start() {
        recording = true
        problem = nil
        commands.isRecordingShortcut = true
        // Lets the recorder hear the show/hide shortcut instead of the window
        // toggling while you're trying to type it.
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let pressed = HotKey(event: event, allowingBareKey: allowsBareKey) {
                problem = pick(pressed)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        commands.isRecordingShortcut = false
        HotKeyCenter.shared.register(state.hotKey)
    }
}

struct Keycap: View {
    let label: String

    init(_ label: String) {
        self.label = label
    }

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 19)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}
