import Foundation

/// Where `AppState` keeps the Harvest credentials. The app uses
/// the Keychain; tests use `InMemoryCredentialStore`, so a test run can never
/// read or overwrite the credentials the real app signed in with.
protocol CredentialStore {
    func load() -> Keychain.Credentials?
    func save(_ credentials: Keychain.Credentials) throws
    func clear()
}

extension Keychain: CredentialStore {}

/// Set once a release build has saved the credentials itself.
let credentialsSavedByReleaseKey = "credentialsSavedByRelease"

extension CredentialStore {
    /// Saves credentials again the first time a release build reads them.
    ///
    /// A Keychain item trusts the build that wrote it: one saved by a build of
    /// your own trusts that certificate and that exact build, so a release
    /// fails both checks and prompts twice on every launch, and "Always Allow"
    /// cannot change an item it does not own. Saved by a release, the item
    /// trusts the release team, which every later release passes too.
    ///
    /// The flag is only set on success, so a save the Keychain refuses is
    /// tried again next launch rather than given up on.
    /// ponytail: switching back to a build of your own and signing in again
    /// leaves the flag set; clear the default if that ever matters.
    func adoptForRelease(_ credentials: Keychain.Credentials, defaults: UserDefaults) {
        guard !defaults.bool(forKey: credentialsSavedByReleaseKey),
              (try? save(credentials)) != nil else { return }
        defaults.set(true, forKey: credentialsSavedByReleaseKey)
    }
}

final class InMemoryCredentialStore: CredentialStore {
    private(set) var saved: Keychain.Credentials?

    func load() -> Keychain.Credentials? { saved }
    func save(_ credentials: Keychain.Credentials) throws { saved = credentials }
    func clear() { saved = nil }
}
