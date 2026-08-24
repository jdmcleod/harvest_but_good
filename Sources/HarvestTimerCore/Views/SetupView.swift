import SwiftUI

struct SetupView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    var isSheet = false

    @State private var token = ""
    @State private var accountId = ""
    @State private var validating = false
    @State private var validationResult: ValidationResult?

    enum ValidationResult: Equatable {
        case success(String)
        case failure(String)
    }

    private var validated: Bool {
        if case .success = validationResult { return true }
        return false
    }

    var body: some View {
        @Bindable var state = state
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top) {
                        Text("Connect to Harvest")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        if isSheet {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                        }
                    }
                    Text("This app controls your Harvest timers with a Personal Access Token — a key that only accesses your own account, which you can revoke anytime.")
                        .foregroundStyle(.secondary)
                }

                step(number: 1, title: "Create a token") {
                    Text("Open Harvest's developer page, sign in, and click **Create new personal access token**. Name it `HarvestTimer`.")
                    Button {
                        NSWorkspace.shared.open(URL(string: "https://id.getharvest.com/developers")!)
                    } label: {
                        Label("Open Harvest Developers", systemImage: "arrow.up.right.square")
                    }
                }

                step(number: 2, title: "Paste your credentials") {
                    Text("Copy the token, then find your **Account ID** — the number shown in the *Choose Account* dropdown on that same page (not your company name).")
                    SecureField("Personal Access Token", text: $token)
                        .textFieldStyle(.roundedBorder)
                    TextField("Account ID (numbers only, e.g. 1234567)", text: $accountId)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 280)
                }

                step(number: 3, title: "Validate & save") {
                    HStack(spacing: 12) {
                        Button {
                            Task { await validate() }
                        } label: {
                            if validating {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Validate")
                            }
                        }
                        .disabled(token.isEmpty || accountId.isEmpty || validating)

                        switch validationResult {
                        case .success(let message):
                            Label(message, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let message):
                            Label(message, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        case nil:
                            EmptyView()
                        }
                    }
                    Text("Your token is stored in the macOS Keychain, never in a file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if isSheet {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "moon.zzz.fill")
                                .foregroundStyle(Color.harvest)
                                .frame(width: 24, height: 24)
                            Text("Idle Detection")
                                .font(.headline)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If the mouse and keyboard sit untouched for this long while a timer runs, the app asks when you come back whether to keep the time, remove it, or log it to another task.")
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                TextField(
                                    "Minutes",
                                    value: $state.afkToleranceMinutes,
                                    format: .number
                                )
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                                Stepper("", value: $state.afkToleranceMinutes, in: 0...480)
                                    .labelsHidden()
                                Text("minutes — 0 turns it off")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.leading, 32)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )

                    DailyGoalsCard()

                    UpdatesCard()
                }

                HStack {
                    if isSheet {
                        Button("Cancel") { dismiss() }
                        if state.credentials != nil {
                            Button("Remove Token", role: .destructive) {
                                state.removeCredentials()
                                dismiss()
                            }
                        }
                    }
                    Spacer()
                    Button("Save & Start") { save() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!validated)
                }
            }
            .padding(24)
        }
        .frame(
            width: isSheet ? 560 : nil,
            height: isSheet ? 680 : nil
        )
    }

    @ViewBuilder
    private func step(number: Int, title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.callout.weight(.bold))
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.harvest.opacity(0.15)))
                Text(title)
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(.leading, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    private func validate() async {
        validating = true
        defer { validating = false }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAccountId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let api = HarvestAPI(credentials: .init(token: trimmedToken, accountId: trimmedAccountId))
        do {
            let user = try await api.currentUser()
            let companyName = (try? await api.company().name).map { " @ \($0)" } ?? ""
            validationResult = .success("Connected as \(user.firstName) \(user.lastName)\(companyName)")
        } catch {
            validationResult = .failure(error.localizedDescription)
        }
    }

    private func save() {
        do {
            try state.saveCredentials(
                token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                accountId: accountId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            if isSheet { dismiss() }
        } catch {
            validationResult = .failure("Couldn't save to Keychain: \(error.localizedDescription)")
        }
    }
}
