import SwiftUI

struct FavoriteDetailsSheet: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let favorite: Favorite
    let isNew: Bool

    @State private var nickname = ""
    @State private var colorIndex: Int?
    @State private var shortcut: String?
    @FocusState private var nicknameFocused: Bool

    private var derivedLabel: String {
        var stripped = favorite
        stripped.nickname = nil
        return stripped.chipLabel
    }

    private var preview: Favorite {
        var preview = favorite
        preview.nickname = nickname.isEmpty ? nil : nickname
        preview.colorIndex = colorIndex
        preview.shortcut = shortcut
        return preview
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isNew ? "Add Favorite" : "Edit Favorite")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 1) {
                Text(favorite.projectName)
                    .font(.callout.weight(.semibold))
                Text("\(favorite.clientName) · \(favorite.taskName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 14) {
                    nicknameField
                    colorField
                    shortcutField
                }
                Spacer()
                previewChip
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(isNew ? "Add Favorite" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear {
            nickname = favorite.nickname ?? ""
            colorIndex = favorite.colorIndex
            shortcut = favorite.shortcut
            nicknameFocused = true
        }
    }

    private var nicknameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nickname (optional)")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(derivedLabel, text: $nickname)
                .pickerSearchFieldStyle()
                .frame(width: 120)
                .focused($nicknameFocused)
                .onChange(of: nickname) { _, new in
                    if new.count > Favorite.maxLabelLength {
                        nickname = String(new.prefix(Favorite.maxLabelLength))
                    }
                }
            Text("Up to \(Favorite.maxLabelLength) characters. Empty uses “\(derivedLabel)”.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Colour")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                swatch(nil, color: palette.forProject(favorite.projectId))
                ForEach(Array(palette.projectColors.enumerated()), id: \.offset) { index, color in
                    swatch(index, color: color)
                }
            }
            Text("The first swatch is the project’s own colour.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var others: [Favorite] {
        state.favorites.filter { $0.id != favorite.id }
    }

    /// The key this favorite's place in the row gives it, unless another
    /// favorite was given that key outright.
    private var placeKey: String? {
        let index = state.favorites.firstIndex { $0.id == favorite.id } ?? state.favorites.count
        guard let key = FavoriteShortcuts.placeKey(at: index),
              !others.contains(where: { $0.shortcut == key }) else { return nil }
        return key
    }

    private func holder(of key: String) -> Favorite? {
        FavoriteShortcuts.favorite(forKey: key, in: others)
    }

    private var shortcutField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Shortcut")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Shortcut", selection: $shortcut) {
                Text(placeKey.map { "By position (\($0))" } ?? "By position (none)")
                    .tag(String?.none)
                Divider()
                ForEach(FavoriteShortcuts.choices, id: \.self) { key in
                    Text(holder(of: key).map { "\(key)  (now \($0.chipLabel))" } ?? key)
                        .tag(Optional(key))
                }
            }
            .labelsHidden()
            .frame(width: 160)
            Text("Press it with the window in front to start this timer.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func swatch(_ index: Int?, color: Color) -> some View {
        let isSelected = colorIndex == index
        return Circle()
            .fill(color)
            .frame(width: 18, height: 18)
            .overlay {
                if index == nil {
                    Image(systemName: "a.circle")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                Circle()
                    .strokeBorder(isSelected ? palette.emphasis : .clear, lineWidth: 2)
                    .padding(-3)
            }
            .contentShape(Circle())
            .onTapGesture { colorIndex = index }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(index == nil ? "Project colour" : "Colour \(index! + 1)")
    }

    private var previewChip: some View {
        VStack(spacing: 4) {
            FavoriteChipLabel(favorite: preview, filled: false)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.accent)
                )
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        if isNew {
            state.addFavorite(preview)
        } else {
            state.updateFavorite(preview)
        }
        dismiss()
    }
}
