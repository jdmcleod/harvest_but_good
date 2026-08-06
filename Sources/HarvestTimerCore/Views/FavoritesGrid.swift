import SwiftUI

struct FavoritesGrid: View {
    @Environment(AppState.self) private var state
    @State private var showingAddSheet = false

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Favorites")
                    .font(.headline)
                Spacer()
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .controlSize(.small)
            }
            if state.favorites.isEmpty {
                Text("No favorites yet. Add a project + task to start timers with one click.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(state.favorites) { favorite in
                        FavoriteCard(favorite: favorite)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .sheet(isPresented: $showingAddSheet) {
            AddFavoriteSheet()
        }
    }
}

private struct FavoriteCard: View {
    @Environment(AppState.self) private var state
    let favorite: Favorite
    @State private var hovering = false

    private var isRunning: Bool {
        guard let running = state.runningEntry else { return false }
        return running.project.id == favorite.projectId && running.task.id == favorite.taskId
    }

    var body: some View {
        Button {
            Task { await state.startFavorite(favorite) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(favorite.clientName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(favorite.projectName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(favorite.taskName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(projectColor(favorite.projectId).opacity(isRunning ? 0.25 : 0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        projectColor(favorite.projectId).opacity(isRunning ? 0.9 : 0.35),
                        lineWidth: isRunning ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    state.removeFavorite(favorite)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
                .help("Remove favorite")
            }
        }
        .onHover { hovering = $0 }
    }
}
