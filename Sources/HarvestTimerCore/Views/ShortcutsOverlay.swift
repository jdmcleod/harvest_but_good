import SwiftUI

/// Every shortcut the app has, each one set by clicking it and pressing the
/// keys. A card inside the window rather than a sheet, which would be sized
/// for itself and outgrow the window it belongs to.
struct ShortcutsOverlay: View {
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            card
                .padding(24)
        }
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.97)))
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                Button("Clear All", action: state.clearBindings)
                    .controlSize(.small)
                    .disabled(state.keyBindings == WindowCommand.defaults)
                    .help("Removes every shortcut but ? and ⌘,, so you can still get back here.")
                Button("Use Suggested", action: state.useSuggestedBindings)
                    .controlSize(.small)
                    .disabled(!hasSuggestionsLeft)
                    .help("Fills in a shortcut for each one that has none. Yours stay as they are.")
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (esc)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            Text("Click a shortcut and press the keys. Bare keys work whenever you aren't typing in a field.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Anywhere") {
                        row("Show or hide the window") {
                            ShowHideRecorder()
                        }
                    }
                    ForEach(WindowCommand.Group.allCases, id: \.self) { group in
                        section(group.rawValue) {
                            ForEach(WindowCommand.allCases.filter { $0.group == group }, id: \.self) { command in
                                row(command.title) { recorder(for: command) }
                            }
                            if group == .timer, !favoriteKeys.isEmpty {
                                row("Start a favorite") {
                                    HStack(spacing: 3) { ForEach(favoriteKeys, id: \.self) { Keycap($0) } }
                                        .padding(.horizontal, 4)
                                        .help("Set under Edit Favorite")
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(width: 440)
        .frame(maxHeight: 520)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var favoriteKeys: [String] {
        let keys = state.favorites.compactMap { state.shortcutKey(for: $0) }
        return keys.count > 3 ? [keys[0], "…", keys[keys.count - 1]] : keys
    }

    private var hasSuggestionsLeft: Bool {
        WindowCommand.allCases.contains { command in
            let suggested = command.suggested
            guard state.keyBindings[command] == nil, state.isFree(suggested) else { return false }
            return !state.keyBindings.values.contains(where: suggested.matches)
        }
    }

    private func recorder(for command: WindowCommand) -> some View {
        ShortcutRecorder(key: state.keyBindings[command]) {
            pick($0, for: command)
        } clear: {
            state.setBinding(nil, for: command)
        }
    }

    private func pick(_ key: HotKey, for command: WindowCommand) -> String? {
        if WindowCommand.isReserved(key) { return "\(key.display) is kept for the app" }
        if state.hotKey.matches(key) { return "\(key.display) shows or hides the window" }
        if key.isBare, let favorite = FavoriteShortcuts.favorite(forKey: key.key, in: state.favorites) {
            return "\(key.display) starts \(favorite.taskName)"
        }
        state.setBinding(key, for: command)
        return nil
    }

    private func close() {
        commands.showingShortcuts = false
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row<Recorder: View>(_ title: String, @ViewBuilder recorder: () -> Recorder) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.callout)
            Spacer(minLength: 8)
            recorder()
        }
    }
}
