import Foundation
import Security

struct Keychain {
    /// What the app uses. Tests build their own under a service name of their
    /// own, so a test run never touches the real credentials.
    static let shared = Keychain(service: "com.rolemodel.HarvestTimer")

    let service: String

    struct Credentials: Equatable {
        let token: String
        let accountId: String
    }

    /// Both halves or nothing: a token without an account is no use, and
    /// leaving one behind would look like being signed in.
    func load() -> Credentials? {
        guard let token = read(account: "token"),
              let accountId = read(account: "accountId") else { return nil }
        return Credentials(token: token, accountId: accountId)
    }

    func save(_ credentials: Credentials) throws {
        try write(account: "token", value: credentials.token)
        try write(account: "accountId", value: credentials.accountId)
    }

    func clear() {
        delete(account: "token")
        delete(account: "accountId")
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
