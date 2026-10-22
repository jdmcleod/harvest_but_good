import Carbon.HIToolbox
import SwiftUI

/// The global shortcut that shows the window from anywhere and, pressed
/// again, hides it and hands focus back to the app you came from.
struct ShortcutCard: View {
    var body: some View {
        SettingsCard(title: "Keyboard Shortcut", systemImage: "keyboard") {
            HotKeyRecorder()
        } content: {
            Text("Show or hide the window from any app. Hiding it this way puts you back where you were.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct HotKeyRecorder: View {
    @Environment(AppState.self) private var state
    @Environment(\.palette) private var palette
    @State private var recording = false
    @State private var monitor: Any?
    @State private var taken: HotKey?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut…" : state.hotKey.display)
                    .font(.system(size: 12.5, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(minWidth: 70, minHeight: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(recording ? palette.accent.opacity(0.15) : Color.primary.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(recording ? palette.accent : Color.primary.opacity(0.15))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click, then press the keys. Escape cancels.")

            if let taken {
                Text("\(taken.display) is taken by another app")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        recording = true
        taken = nil
        HotKeyCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let key = HotKey(event: event) {
                // Tried before it is kept, so a combination another app
                // owns never replaces one that works.
                if HotKeyCenter.shared.register(key) {
                    state.hotKey = key
                } else {
                    taken = key
                }
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
        HotKeyCenter.shared.register(state.hotKey)
    }
}
