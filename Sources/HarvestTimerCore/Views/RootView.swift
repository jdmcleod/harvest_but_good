import SwiftUI

public struct RootView: View {
    @Environment(AppState.self) private var state

    public init() {}

    public var body: some View {
        Group {
            if state.needsSetup {
                SetupView()
            } else {
                MainView()
            }
        }
        .frame(
            minWidth: 720, idealWidth: 960, maxWidth: .infinity,
            minHeight: 480, idealHeight: 640, maxHeight: .infinity
        )
        .tint(.harvest)
    }
}
