import SwiftUI

/// First run: walks through making a token and checks it before saving.
/// Changing it later happens in the settings sheet's account card.
struct SetupView: View {
    @Environment(\.palette) private var palette
    @Environment(AppState.self) private var state

    @State private var draft = CredentialsDraft()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect to Harvest")
                        .font(.title2.weight(.semibold))
                    Text("This app controls your Harvest timers with a Personal Access Token — a key that only accesses your own account, which you can revoke anytime.")
                        .foregroundStyle(.secondary)
                }

                step(number: 1, title: "Create a token") {
                    Text("Open Harvest's developer page, sign in, and click **Create new personal access token**. Name it `HarvestTimer`.")
                    Button {
                        NSWorkspace.shared.open(HarvestAPI.developersURL)
                    } label: {
                        Label("Open Harvest Developers", systemImage: "arrow.up.right.square")
                    }
                }

                step(number: 2, title: "Paste your credentials") {
                    Text("Copy the token, then find your **Account ID** — the number shown in the *Choose Account* dropdown on that same page (not your company name).")
                    SecureField("Personal Access Token", text: $draft.token)
                        .textFieldStyle(.roundedBorder)
                    TextField("Account ID (numbers only, e.g. 1234567)", text: $draft.accountId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                step(number: 3, title: "Validate & save") {
                    CredentialsCheck(draft: draft)
                    Text("Your token is stored in the macOS Keychain, never in a file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Spacer()
                    Button("Save & Start") { draft.save(into: state) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!draft.canSave)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func step(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.callout.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(palette.accent.opacity(0.15)))
                Text(title)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 32)
        }
        .settingsPanel()
    }
}
