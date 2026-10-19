import SwiftUI

/// Who the app is connected as, folded to one line. Change… opens it into a
/// form for a new token, which leaves the current one working until saved.
struct AccountCard: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    /// Present only while a new token is being typed in.
    @State private var draft: CredentialsDraft?
    @State private var confirmingRemoval = false
    @FocusState private var tokenFocused: Bool

    private static let avatarSize: CGFloat = 32
    private static let edge: CGFloat = 14
    private static let avatarGap: CGFloat = 12
    /// Lines the form up under the name rather than the avatar.
    private static let formIndent = edge + avatarSize + avatarGap

    var body: some View {
        VStack(spacing: 0) {
            identity
                .padding(.horizontal, Self.edge)
                .padding(.vertical, 12)
            if let draft {
                Divider()
                form(draft)
                Divider()
                actions(draft)
            }
        }
        .settingsPanel(padding: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(palette.accent.opacity(draft == nil ? 0 : 0.45))
        )
        .confirmationDialog(
            "Remove your Harvest token?",
            isPresented: $confirmingRemoval
        ) {
            Button("Remove Token", role: .destructive) {
                state.removeCredentials()
                dismiss()
            }
        } message: {
            Text("The app stops syncing until you connect again.")
        }
    }

    private var identity: some View {
        HStack(spacing: Self.avatarGap) {
            Text(state.currentUser?.initials ?? "H")
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.accent)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .background(Circle().fill(palette.accent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                // Until the first sync after connecting, all there is to go
                // on is the account id.
                Text(state.currentUser?.fullName ?? "Harvest account")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(palette.success)
                        .frame(width: 7, height: 7)
                    Text(connection)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if draft == nil {
                Button("Change…") {
                    draft = CredentialsDraft(accountId: state.credentials?.accountId ?? "")
                }
            } else {
                Button("Cancel") { draft = nil }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func form(_ draft: CredentialsDraft) -> some View {
        @Bindable var draft = draft
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your current token keeps working until you save.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Link(destination: HarvestAPI.developersURL) {
                    Text("Get a token \(Image(systemName: "arrow.up.right"))")
                        .font(.callout.weight(.medium))
                }
                .foregroundStyle(palette.accent)
                .pointingCursor()
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Personal Token")
                    SecureField("Paste a new token", text: $draft.token)
                        .textFieldStyle(.roundedBorder)
                        .focused($tokenFocused)
                        .onAppear { tokenFocused = true }
                }
                GridRow {
                    Text("Account ID")
                    TextField("e.g. 1234567", text: $draft.accountId)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    CredentialsCheck(draft: draft)
                }
            }
            .font(.callout)
        }
        .padding(.leading, Self.formIndent)
        .padding([.trailing, .vertical], Self.edge)
    }

    private func actions(_ draft: CredentialsDraft) -> some View {
        HStack {
            Button("Remove Token…", role: .destructive) { confirmingRemoval = true }
                .buttonStyle(.borderless)
                .foregroundStyle(palette.danger)
            Spacer()
            Button("Save Token") {
                if draft.save(into: state) { self.draft = nil }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canSave)
        }
        .padding(.horizontal, Self.edge)
        .padding(.vertical, 10)
        .background(Color.primary.opacity(0.03))
    }

    private var connection: String {
        if let company = state.company { return "Connected to \(company.name)" }
        return state.credentials.map { "Account \($0.accountId)" } ?? "Not connected"
    }
}
