import SwiftUI

/// How long the mouse and keyboard can sit still before the app asks about
/// the time.
struct IdleDetectionCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        SettingsCard(title: "Idle Detection", systemImage: "moon.zzz.fill") {
            HStack(spacing: 6) {
                TextField("Minutes", value: $state.afkToleranceMinutes, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                Stepper("", value: $state.afkToleranceMinutes, in: 0...480)
                    .labelsHidden()
                Text("min")
                    .foregroundStyle(.secondary)
            }
        } content: {
            Text("Ask what to do with the time when the mouse and keyboard sit untouched this long. 0 turns it off.")
                .foregroundStyle(.secondary)
        }
    }
}
