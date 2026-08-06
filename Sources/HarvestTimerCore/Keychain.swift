import Foundation
import Security

enum Keychain {
    private static let service = "com.rolemodel.HarvestTimer"

    struct Credentials: Equatable {
        let token: String
        let accountId: String
    }

    static func load() -> Credentials? {
        guard let token = read(account: "token"),
              let accountId = read(account: "accountId") else { return nil }
        return Credentials(token: token, accountId: accountId)
    }

    static func save(_ credentials: Credentials) throws {
        try write(account: "token", value: credentials.token)
        try write(account: "accountId", value: credentials.accountId)
    }

    static func clear() {
        delete(account: "token")
        delete(account: "accountId")
    }

    private static func read(account: String) -> String? {
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

    private static func write(account: String, value: String) throws {
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

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
