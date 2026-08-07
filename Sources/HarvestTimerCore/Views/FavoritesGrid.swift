import SwiftUI

struct FavoriteChips: View {
    @Environment(AppState.self) private var state
    @State private var showingAddSheet = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(state.favorites) { favorite in
                FavoriteChip(favorite: favorite)
            }
            Button {
                showingAddSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .pointingCursor()
            .help("Add favorite")
        }
        .sheet(isPresented: $showingAddSheet) {
            AddFavoriteSheet()
        }
    }
}

private struct FavoriteChip: View {
    @Environment(AppState.self) private var state
    let favorite: Favorite
    @State private var hovering = false

    private var isRunning: Bool {
        guard let running = state.runningEntry else { return false }
        return running.project.id == favorite.projectId && running.task.id == favorite.taskId
    }

    private var displayName: String {
        let name = favorite.projectName
        if let separator = name.range(of: #"\s*[–—]\s*|\s+-\s+"#, options: .regularExpression) {
            let stripped = name[separator.upperBound...].trimmingCharacters(in: .whitespaces)
            if !stripped.isEmpty { return stripped }
        }
        return name
    }

    var body: some View {
        Button {
            Task { await state.startFavorite(favorite) }
        } label: {
            Text(displayName.uppercased().prefix(6))
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .rotationEffect(.degrees(90))
                .fixedSize()
                .foregroundStyle(isRunning ? .white : projectColor(favorite.projectId))
                .frame(width: 14, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(isRunning ? projectColor(favorite.projectId).opacity(0.9) : Color.white.opacity(0.9))
                )
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .overlay(alignment: .bottom) {
            if hovering {
                Text("\(favorite.projectName) · \(favorite.taskName)")
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary)
                    )
                    .fixedSize()
                    .offset(y: 30)
                    .allowsHitTesting(false)
            }
        }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove Favorite", systemImage: "trash", role: .destructive) {
                state.removeFavorite(favorite)
            }
        }
    }
}
