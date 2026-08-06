import SwiftUI

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
                EntryList()
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

struct ErrorBanner: View {
    @Environment(AppState.self) private var state
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .lineLimit(2)
                .font(.callout)
            Spacer()
            Button {
                state.syncError = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .pointingCursor()
        }
        .padding(8)
        .background(.yellow.opacity(0.12))
    }
}

func projectColor(_ projectId: Int64) -> Color {
    let palette: [Color] = [
        .blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown,
    ]
    return palette[Int(projectId % Int64(palette.count))]
}
