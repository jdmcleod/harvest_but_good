import SwiftUI

/// Every key the window answers to, read off the same table the key monitor
/// and the palette use, so it can't drift from what the keys really do.
/// A card inside the window rather than a sheet, which would be sized for
/// itself and outgrow the window it belongs to.
struct ShortcutsOverlay: View {
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Row: Identifiable {
        let title: String
        let keys: [String]
        var editable = false
        var id: String { title }
    }

    private var groups: [(title: String, rows: [Row])] {
        let caps = commands.keycaps
        func rows(_ list: [(WindowCommand, String?)]) -> [Row] {
            list.compactMap { command, title in
                caps[command].map { Row(title: title ?? command.title, keys: $0) }
            }
        }
        let allFavoriteKeys = state.favorites.compactMap { state.shortcutKey(for: $0) }
        let favoriteKeys = allFavoriteKeys.count > 3
            ? [allFavoriteKeys[0], "…", allFavoriteKeys[allFavoriteKeys.count - 1]]
            : allFavoriteKeys
        return [
            ("Anywhere", [
                Row(title: "Show or hide the window", keys: state.hotKey.displayParts, editable: true),
                Row(title: "Open with the command palette", keys: state.openToPaletteHotKey.displayParts, editable: true),
            ]),
            ("Timers", [Row(title: "Command palette", keys: state.paletteHotKey.displayParts, editable: true)]
                + rows([(.startTimer, nil), (.toggleTimer, nil), (.notes, "Write a note on the timer"),
                        (.addFifteen, nil), (.takeFifteen, nil)])
                + (favoriteKeys.isEmpty ? [] : [Row(title: "Start a favorite", keys: favoriteKeys, editable: true)])),
            ("Moving around", rows([(.nextEntry, "Next entry (or ↓)"), (.previousEntry, "Previous entry (or ↑)"),
                                     (.previousDay, "Previous day (or ←)"), (.nextDay, "Next day (or →)"),
                                     (.previousWeek, nil), (.nextWeek, nil), (.today, nil),
                                     (.settings, "Settings"), (.shortcuts, "This sheet")])),
            ("Picked or running entry", rows([(.toggleSelected, "Start or stop it"), (.editHours, nil),
                                               (.changeProjectTask, "Change project or task"), (.moveTime, "Move time"),
                                               (.trim, nil), (.deleteEntry, "Delete"),
                                               (.clearSelection, "Let go of the picked entry")])),
        ]
    }

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
                Button("Change…") {
                    close()
                    commands.showingSettings = true
                }
                .controlSize(.small)
                Button(action: close) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (esc or ?)")
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 4)
            Text("Bare keys work whenever you aren't typing in a field.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups, id: \.title) { group($0) }
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

    private func close() {
        commands.showingShortcuts = false
    }

    private func group(_ group: (title: String, rows: [Row])) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(group.title.uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
            ForEach(group.rows) { row in
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(.callout)
                    Spacer(minLength: 8)
                    if row.editable {
                        Text("EDITABLE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.primary.opacity(0.15)))
                    }
                    HStack(spacing: 3) {
                        ForEach(Array(row.keys.enumerated()), id: \.offset) { _, key in Keycap(key) }
                    }
                }
            }
        }
    }
}
