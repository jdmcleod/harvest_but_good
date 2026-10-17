import SwiftUI

/// The switch for wearing your own colors, and the pickers for them.
struct CustomColorsCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(
            title: "Custom Colors",
            systemImage: "paintpalette.fill",
            isOn: $state.customColors.isEnabled
        ) {
            Text("Swap the app's colors for your own. Outlines and the goal bar follow the accent.")
                .foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ColorRow(title: "Header", hex: $state.customColors.header)
                ColorRow(title: "Accent", hex: $state.customColors.accent)
                ColorRow(title: "Start button", hex: $state.customColors.start)
                ColorRow(title: "Highlight", hex: $state.customColors.highlight)
            }
            Button("Reset to Defaults") { state.customColors.resetColors() }
                .disabled(state.customColors.usesDefaultColors)
        }
    }
}

private struct ColorRow: View {
    let title: String
    @Binding var hex: UInt32

    private var color: Binding<Color> {
        Binding(
            get: { Color(hex: hex) },
            set: { hex = CustomColors.hex(of: $0) }
        )
    }

    var body: some View {
        GridRow {
            Text(title)
            ColorPicker("", selection: color, supportsOpacity: false)
                .labelsHidden()
        }
    }
}
