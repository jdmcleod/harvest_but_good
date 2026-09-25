import Foundation

/// Where `AppState` keeps the Harvest and Almanac credentials. The app uses
/// the Keychain; tests use `InMemoryCredentialStore`, so a test run can never
/// read or overwrite the credentials the real app signed in with.
protocol CredentialStore {
    func load() -> Keychain.Credentials?
    func save(_ credentials: Keychain.Credentials) throws
    func clear()
}

extension Keychain: CredentialStore {}

final class InMemoryCredentialStore: CredentialStore {
    private(set) var saved: Keychain.Credentials?

    func load() -> Keychain.Credentials? { saved }
    func save(_ credentials: Keychain.Credentials) throws { saved = credentials }
    func clear() { saved = nil }
}
