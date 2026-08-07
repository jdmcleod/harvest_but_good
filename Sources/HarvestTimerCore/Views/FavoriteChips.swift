import SwiftUI

struct FavoriteChips: View {
    /// The row's own coordinate space, so a drag is measured against something
    /// that stays put while the chips move.
    static let dragSpace = "favoriteChips"

    @Environment(AppState.self) private var state
    @State private var showingAddSheet = false
    @State private var editing: Favorite?
    @State private var dragging: ChipDrag?

    /// A reorder in flight: which chip, where it started, how far it has come,
    /// and the index it would land on if the mouse came up now.
    private struct ChipDrag {
        let id: String
        let from: Int
        var translation: CGFloat
        var to: Int
    }

    var body: some View {
        HStack(spacing: FavoriteOrder.chipSpacing) {
            // Enumerated for the index the drag maths needs, but keyed on the
            // favourite's own id so a committed reorder animates instead of
            // cutting.
            ForEach(Array(state.favorites.enumerated()), id: \.element.id) { index, favorite in
                FavoriteChip(
                    favorite: favorite,
                    index: index,
                    count: state.favorites.count,
                    isLifted: dragging?.id == favorite.id,
                    tooltipsSuppressed: dragging != nil,
                    onEdit: { editing = favorite },
                    onDragChanged: { width in track(index: index, id: favorite.id, width: width) },
                    onDragEnded: commit
                )
                .offset(x: offset(for: index))
                // The chip under the pointer must track it exactly; animating it
                // would have it chase a target that is still moving, which reads
                // as a jitter. Its neighbours are the ones that glide.
                .animation(
                    dragging?.id == favorite.id ? nil : .snappy(duration: 0.15),
                    value: offset(for: index)
                )
                .zIndex(dragging?.id == favorite.id ? 1 : 0)
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
        // A drag is measured against the row, which does not move. Against the
        // chip's own space — the default — offsetting the chip would shift the
        // origin the next translation is measured from, and the chip would
        // oscillate instead of following the pointer.
        .coordinateSpace(name: Self.dragSpace)
        .sheet(isPresented: $showingAddSheet) {
            AddFavoriteSheet()
        }
        .sheet(item: $editing) { favorite in
            FavoriteDetailsSheet(favorite: favorite, isNew: false)
        }
    }

    private func offset(for index: Int) -> CGFloat {
        guard let dragging else { return 0 }
        if index == dragging.from {
            return FavoriteOrder.heldTranslation(
                dragging.translation,
                from: index,
                count: state.favorites.count
            )
        }
        return FavoriteOrder.displacement(of: index, draggedFrom: dragging.from, to: dragging.to)
    }

    private func track(index: Int, id: String, width: CGFloat) {
        let to = FavoriteOrder.destination(
            from: index,
            translation: width,
            count: state.favorites.count
        )
        if dragging?.id == id {
            dragging?.translation = width
            dragging?.to = to
        } else {
            dragging = ChipDrag(id: id, from: index, translation: width, to: to)
        }
    }

    private func commit() {
        guard let drag = dragging else { return }
        dragging = nil
        // The lifted chip is up to half a pitch from where it will settle, so
        // the last few points are animated rather than snapped.
        withAnimation(.snappy(duration: 0.12)) {
            state.moveFavorite(from: drag.from, to: drag.to)
        }
    }
}

/// The chip itself, without any behaviour: shared with the details sheet so the
/// preview there is the real thing rather than a lookalike.
struct FavoriteChipLabel: View {
    let favorite: Favorite
    let filled: Bool

    var body: some View {
        Text(favorite.chipLabel)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .rotationEffect(.degrees(90))
            .fixedSize()
            .foregroundStyle(filled ? .white : Color.forFavorite(favorite))
            .frame(width: FavoriteOrder.chipWidth, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(filled ? Color.forFavorite(favorite).opacity(0.9) : Color.white.opacity(0.9))
            )
    }
}

private struct FavoriteChip: View {
    @Environment(AppState.self) private var state
    let favorite: Favorite
    let index: Int
    let count: Int
    let isLifted: Bool
    let tooltipsSuppressed: Bool
    let onEdit: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void

    @State private var hovering = false
    /// Set the moment the pointer travels far enough to be a reorder. The
    /// button's action fires on the same mouse-up that ends the drag, and that
    /// action starts a Harvest timer — so a drag has to be able to say no.
    @State private var moved = false

    private var isRunning: Bool {
        guard let running = state.runningEntry else { return false }
        return running.project.id == favorite.projectId && running.task.id == favorite.taskId
    }

    var body: some View {
        Button {
            guard !moved else { return }
            Task { await state.startFavorite(favorite) }
        } label: {
            FavoriteChipLabel(favorite: favorite, filled: isRunning)
                .scaleEffect(isLifted ? 1.08 : 1)
                .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: 4, y: 2)
                .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .pointingCursor()
        .simultaneousGesture(
            // 4pt of slack: a click with a shaky hand is still a click, and a
            // click never reaches onChanged at all. Measured against the row,
            // not the chip, which moves.
            DragGesture(minimumDistance: 4, coordinateSpace: .named(FavoriteChips.dragSpace))
                .onChanged { value in
                    moved = true
                    hovering = false
                    onDragChanged(value.translation.width)
                }
                .onEnded { _ in
                    onDragEnded()
                    // Cleared a turn later, not now: the button's action runs on
                    // this same mouse-up and must still see the drag.
                    Task { @MainActor in moved = false }
                }
        )
        .overlay(alignment: .bottom) {
            // Suppressed for every chip while any drag is live, or a neighbour
            // sliding under a stationary pointer pops its own tooltip.
            if hovering, !tooltipsSuppressed {
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
            Button("Edit Favorite…", systemImage: "pencil", action: onEdit)
            // Dragging is quicker, but a 14pt chip is a small thing to grab, so
            // there is a menu path too.
            Button("Move Left", systemImage: "arrow.left") {
                state.moveFavorite(from: index, to: index - 1)
            }
            .disabled(index == 0)
            Button("Move Right", systemImage: "arrow.right") {
                state.moveFavorite(from: index, to: index + 1)
            }
            .disabled(index >= count - 1)
            Divider()
            Button("Remove Favorite", systemImage: "trash", role: .destructive) {
                state.removeFavorite(favorite)
            }
        }
    }
}
