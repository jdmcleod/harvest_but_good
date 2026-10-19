import Foundation
import Observation

/// A token and account id being typed in, and whether Harvest accepts them.
///
/// Shared by first-run setup and the settings sheet's account card, so both
/// validate the same way and neither can save a pair Harvest has turned down.
@MainActor
@Observable
final class CredentialsDraft {
    enum Validation: Equatable {
        case success(String)
        case failure(String)
    }

    // An edit after a check makes its answer stale, so it goes.
    var token = "" {
        didSet { if token != oldValue { validation = nil } }
    }
    var accountId = "" {
        didSet { if accountId != oldValue { validation = nil } }
    }
    private(set) var isValidating = false
    private(set) var validation: Validation?

    /// Builds the client a check goes through; tests hand in a fake.
    private let makeClient: (Keychain.Credentials) -> HarvestClient

    init(
        accountId: String = "",
        makeClient: @escaping (Keychain.Credentials) -> HarvestClient = { HarvestAPI(credentials: $0) }
    ) {
        self.accountId = accountId
        self.makeClient = makeClient
    }

    var credentials: Keychain.Credentials {
        Keychain.Credentials(
            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
            accountId: accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var canValidate: Bool {
        !credentials.token.isEmpty && !credentials.accountId.isEmpty && !isValidating
    }

    var canSave: Bool {
        if case .success = validation { return true }
        return false
    }

    func validate() async {
        isValidating = true
        defer { isValidating = false }
        let api = makeClient(credentials)
        do {
            let user = try await api.currentUser()
            // The company only flavours the message, so its failure is no
            // reason to call a working token broken.
            let companyName = (try? await api.company()).map { " @ \($0.name)" } ?? ""
            validation = .success("Connected as \(user.fullName)\(companyName)")
        } catch {
            validation = .failure(error.localizedDescription)
        }
    }

    /// Hands the checked pair to `state`. Returns whether it stuck, leaving
    /// the reason in `validation` when the Keychain refuses it.
    @discardableResult
    func save(into state: AppState) -> Bool {
        guard canSave else { return false }
        do {
            try state.saveCredentials(token: credentials.token, accountId: credentials.accountId)
            return true
        } catch {
            validation = .failure("Couldn't save to Keychain: \(error.localizedDescription)")
            return false
        }
    }
}
