import Carbon.HIToolbox
import SwiftUI

/// The shortcuts someone can pick for themselves: two that work from any app
/// and the palette's own, which only works with the window in front.
struct ShortcutCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(title: "Keyboard Shortcuts", systemImage: "keyboard") {
            EmptyView()
        } content: {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row(
                    "Show or hide the window",
                    detail: "From any app. Hiding it this way puts you back where you were.",
                    recorder: HotKeyRecorder(key: $state.hotKey, slot: .showHide)
                )
                row(
                    "Open with the command palette",
                    detail: "From any app, with the palette already up.",
                    recorder: HotKeyRecorder(key: $state.openToPaletteHotKey, slot: .openToPalette)
                )
                row(
                    "Command palette",
                    detail: "While the window is in front. Press ? there for every other key.",
                    recorder: HotKeyRecorder(key: $state.paletteHotKey, slot: nil)
                )
            }
        }
    }

    private func row(_ title: String, detail: String, recorder: HotKeyRecorder) -> some View {
        GridRow {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            recorder
                .gridColumnAlignment(.trailing)
        }
    }
}

private struct HotKeyRecorder: View {
    @Environment(\.palette) private var palette
    @Binding var key: HotKey
    /// Nil for a shortcut that only works inside the app, which no other app
    /// can have taken.
    let slot: HotKeySlot?
    @State private var recording = false
    @State private var monitor: Any?
    @State private var taken: HotKey?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            Button {
                recording ? stop() : start()
            } label: {
                Text(recording ? "Type a shortcut…" : key.display)
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
            } else if let picked = HotKey(event: event) {
                // Tried before it is kept, so a combination another app
                // owns never replaces one that works.
                if let slot, !HotKeyCenter.shared.register(picked, for: slot) {
                    taken = picked
                } else {
                    key = picked
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
        HotKeyCenter.shared.resume()
    }
}
