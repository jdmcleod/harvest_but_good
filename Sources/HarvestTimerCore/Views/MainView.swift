import SwiftUI

/// Both panes size their header rows to this so the scroll areas beneath
/// them (and their scroll bars) start at the same height.
enum PanelHeader {
    static let height: CGFloat = 40
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @Environment(WindowCommands.self) private var commands

    var body: some View {
        @Bindable var state = state
        @Bindable var commands = commands
        VStack(spacing: 0) {
            WeekHeader(showingSettings: $commands.showingSettings)
                .zIndex(1)
            Divider()
            HSplitView {
                EntryList(openSettings: { commands.showingSettings = true })
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                DayTimelineView()
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = state.syncError {
                ErrorBanner(message: error)
            }
        }
        .sheet(isPresented: $commands.showingSettings) {
            SettingsView()
        }
        .overlay {
            if commands.showingPalette {
                CommandPalette()
            } else if commands.showingShortcuts {
                ShortcutsOverlay()
            }
        }
        .animation(.snappy(duration: 0.15), value: commands.showingShortcuts)
        .animation(.snappy(duration: 0.15), value: commands.showingPalette)
        .sheet(item: $state.afkPrompt) { prompt in
            AFKPromptView(prompt: prompt)
        }
        .task {
            await state.sync()
        }
    }
}
