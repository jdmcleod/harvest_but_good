import SwiftUI

/// The Validate button and what it found, shared by first-run setup and the
/// account card so the two check a token the same way.
struct CredentialsCheck: View {
    let draft: CredentialsDraft

    var body: some View {
        HStack(spacing: 12) {
            Button {
                Task { await draft.validate() }
            } label: {
                if draft.isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Validate")
                }
            }
            .disabled(!draft.canValidate)

            ValidationLabel(validation: draft.validation)
        }
    }
}

/// What the last check said, or nothing before one.
private struct ValidationLabel: View {
    @Environment(\.palette) private var palette
    let validation: CredentialsDraft.Validation?

    var body: some View {
        switch validation {
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(palette.success)
        case .failure(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(palette.danger)
        case nil:
            EmptyView()
        }
    }
}
