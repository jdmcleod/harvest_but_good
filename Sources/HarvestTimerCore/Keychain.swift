import Foundation
import Security

struct Keychain {
    /// What the app uses. Tests build their own under a service name of their
    /// own, so a test run never touches the real credentials.
    static let shared = Keychain(service: "com.rolemodel.HarvestTimer")

    let service: String

    struct Credentials: Equatable, Codable {
        let token: String
        let accountId: String
    }

    /// One item, not two. macOS asks permission per keychain item, so a token
    /// and an account stored apart meant two password prompts every launch.
    static let account = "credentials"

    /// What versions before the single-item move wrote, kept only so those
    /// installs can be read once and rewritten.
    private static let legacyAccounts = (token: "token", accountId: "accountId")

    /// Both halves or nothing: a token without an account is no use, and
    /// leaving one behind would look like being signed in.
    func load() -> Credentials? {
        if let json = read(account: Self.account),
           let credentials = try? JSONDecoder().decode(Credentials.self, from: Data(json.utf8)) {
            return credentials
        }
        return migrateLegacyCredentials()
    }

    func save(_ credentials: Credentials) throws {
        let json = try JSONEncoder().encode(credentials)
        try write(account: Self.account, value: String(decoding: json, as: UTF8.self))
        clearLeg()
    }

    func clear() {
        delete(account: Self.account)
        clearLeg()
    }

    /// Reads the old pair — costing the two prompts one last time — and writes
    /// them back as one item so the next launch only asks once. A failed
    /// rewrite is not fatal: the credentials are still good for this run.
    private func migrateLegacyCredentials() -> Credentials? {
        guard let token = read(account: Self.legacyAccounts.token),
              let accountId = read(account: Self.legacyAccounts.accountId) else { return nil }
        let credentials = Credentials(token: token, accountId: accountId)
        try? save(credentials)
        return credentials
    }

    private func clearLeg() {
        delete(account: Self.legacyAccounts.token)
        delete(account: Self.legacyAccounts.accountId)
    }

    func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Replaces rather than updates: the old item goes first, so a second
    /// save does not collide with the first.
    func write(account: String, value: String) throws {
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
