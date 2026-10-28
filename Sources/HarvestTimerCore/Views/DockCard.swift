import SwiftUI

/// Off by default: the app lives in the menu bar and stays out of the Dock.
struct DockCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(title: "Show in Dock", systemImage: "dock.rectangle") {
            FeatureSwitch(isOn: $state.showsInDock)
        } content: {
            Text("Keep an icon in the Dock so Cmd-Tab can switch to the app.")
                .foregroundStyle(.secondary)
        }
    }
}
