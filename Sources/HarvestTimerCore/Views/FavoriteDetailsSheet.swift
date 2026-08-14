import SwiftUI

struct FavoriteDetailsSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let favorite: Favorite
    let isNew: Bool

    @State private var nickname = ""
    @State private var colorIndex: Int?
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
                swatch(nil, color: Color.forProject(favorite.projectId))
                ForEach(Array(Color.projectPalette.enumerated()), id: \.offset) { index, color in
                    swatch(index, color: color)
                }
            }
            Text("The first swatch is the project’s own colour.")
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
                    .strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2)
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
                        .fill(Color.harvest)
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
