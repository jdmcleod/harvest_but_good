import Foundation
import Observation

/// Who we are talking to Harvest as: the credentials, the client they build,
/// and the two account facts a sync learns — which user the entries belong to
/// and where the account's pages live.
@MainActor
@Observable
public final class Session {
    private(set) var credentials: Keychain.Credentials?
    /// Set by tests, which stand in their own client rather than reach Harvest.
    private let injectedClient: HarvestClient?
    private var userId: Int64?
    private var baseUri: String?

    /// Reads the saved credentials and talks to the real Harvest.
    public init() {
        injectedClient = nil
        credentials = Keychain.shared.load()
    }

    /// Talks to `client` and leaves the Keychain alone.
    public init(client: HarvestClient) {
        injectedClient = client
        credentials = nil
    }

    public var needsSetup: Bool { credentials == nil }

    public var client: HarvestClient? {
        injectedClient ?? credentials.map { HarvestAPI(credentials: $0) }
    }

    public func save(token: String, accountId: String) throws {
        let credentials = Keychain.Credentials(token: token, accountId: accountId)
        try Keychain.shared.save(credentials)
        self.credentials = credentials
        forgetAccount()
    }

    public func clear() {
        Keychain.shared.clear()
        credentials = nil
        forgetAccount()
    }

    private func forgetAccount() {
        userId = nil
        baseUri = nil
    }

    /// The id of the user whose entries we sync, asked for once per token.
    func resolveUserId(using api: HarvestClient) async throws -> Int64 {
        if let userId { return userId }
        let id = try await api.currentUser().id
        userId = id
        return id
    }

    /// Where the account's pages live, asked for once per token.
    func resolveBaseUri(using api: HarvestClient) async throws {
        guard baseUri == nil else { return }
        baseUri = try await api.company().baseUri
    }

    /// The project's page on the Harvest site, once a sync has learned where
    /// the account lives.
    public func projectURL(for projectId: Int64) -> URL? {
        baseUri.flatMap { URL(string: "\($0)/projects/\(projectId)") }
    }
}
