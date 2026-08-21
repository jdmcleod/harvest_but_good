import SwiftUI

/// Both panes size their header rows to this so the scroll areas beneath
/// them (and their scroll bars) start at the same height.
enum PanelHeader {
    static let height: CGFloat = 40
}

struct MainView: View {
    @Environment(AppState.self) private var state
    @State private var showingSettings = false

    var body: some View {
        @Bindable var state = state
        VStack(spacing: 0) {
            WeekHeader(showingSettings: $showingSettings)
                .zIndex(1)
            Divider()
            HSplitView {
                EntryList(openSettings: { showingSettings = true })
                    .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                DayTimelineView()
                    .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
            }
            if let error = state.syncError {
                ErrorBanner(message: error)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SetupView(isSheet: true)
        }
        .sheet(item: $state.afkPrompt) { prompt in
            AFKPromptView(prompt: prompt)
        }
        .task {
            await state.sync()
        }
    }
}
