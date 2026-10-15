import SwiftUI

struct ErrorBanner: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning)
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
        .background(palette.warning.opacity(0.12))
    }
}
