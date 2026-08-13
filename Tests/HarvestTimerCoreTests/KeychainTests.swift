import Foundation
import Testing

@testable import HarvestTimerCore

/// A keychain of its own for each case, so a test run never reads or writes
/// the credentials the real app is using.
private func scratchKeychain() -> Keychain {
    Keychain(service: "com.rolemodel.HarvestTimer.tests.\(UUID().uuidString)")
}

/// Whether this machine will let an unsigned test binary write to the
/// keychain at all. On a build server without a login keychain it will not,
/// and the suite is skipped rather than failed for it.
private let keychainWorks: Bool = {
    let keychain = scratchKeychain()
    defer { keychain.clear() }
    do {
        try keychain.save(Keychain.Credentials(token: "probe", accountId: "probe"))
        return keychain.load() != nil
    } catch {
        return false
    }
}()

@Test("Keychain", .enabled(if: keychainWorks, "no writable keychain here"))
func runKeychainTests() {
    test("credentials come back as they went in") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }
        let credentials = Keychain.Credentials(token: "a-token", accountId: "12345")

        try keychain.save(credentials)
        expect(keychain.load() == credentials, "should read back what was saved")
    }

    test("nothing saved reads as nothing") {
        expect(scratchKeychain().load() == nil, "a fresh keychain holds no credentials")
    }

    test("saving again replaces rather than piles up") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        try keychain.save(Keychain.Credentials(token: "first", accountId: "1"))
        try keychain.save(Keychain.Credentials(token: "second", accountId: "2"))
        expect(keychain.load()?.token == "second", "the newer token should win")
        expect(keychain.load()?.accountId == "2", "and the newer account with it")
    }

    test("clearing leaves nothing behind") {
        let keychain = scratchKeychain()
        try keychain.save(Keychain.Credentials(token: "a-token", accountId: "12345"))
        keychain.clear()

        expect(keychain.load() == nil, "signing out should clear the credentials")
        expect(keychain.read(account: Keychain.account) == nil, "the item should be gone")
    }

    test("clearing an empty keychain is not a failure") {
        let keychain = scratchKeychain()
        keychain.clear()
        keychain.clear()
        expect(keychain.load() == nil, "clearing twice should be as quiet as once")
    }

    test("half the old credentials read as none at all") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        // A save that failed part way, or an older version that wrote one key.
        try keychain.write(account: "token", value: "a-token")
        expect(keychain.load() == nil, "a token with no account is not being signed in")

        keychain.delete(account: "token")
        try keychain.write(account: "accountId", value: "12345")
        expect(keychain.load() == nil, "nor is an account with no token")
    }

    test("a garbled item reads as nothing rather than crashing") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        try keychain.write(account: Keychain.account, value: "not json")
        expect(keychain.load() == nil, "unreadable credentials are no credentials")
        expect(keychain.read(account: Keychain.account) == nil, "and it should not be left to prompt for")
    }

    test("credentials saved by an older version still load") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        try keychain.write(account: "token", value: "a-token")
        try keychain.write(account: "accountId", value: "12345")
        expect(
            keychain.load() == Keychain.Credentials(token: "a-token", accountId: "12345"),
            "the old pair should read back as credentials"
        )
    }

    test("loading an older version's credentials moves them into one item") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        try keychain.write(account: "token", value: "a-token")
        try keychain.write(account: "accountId", value: "12345")
        _ = keychain.load()

        expect(keychain.read(account: Keychain.account) != nil, "the pair should be rewritten as one")
        expect(keychain.read(account: "token") == nil, "the old token should be cleaned up")
        expect(keychain.read(account: "accountId") == nil, "and the old account with it")
        expect(keychain.load()?.token == "a-token", "and it should still read back after the move")
    }

    test("saving cleans up an older version's items") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }

        try keychain.write(account: "token", value: "stale")
        try keychain.write(account: "accountId", value: "stale")
        try keychain.save(Keychain.Credentials(token: "fresh", accountId: "1"))

        expect(keychain.read(account: "token") == nil, "no stale token should be left to prompt for")
        expect(keychain.read(account: "accountId") == nil, "nor a stale account")
        expect(keychain.load()?.token == "fresh", "and the new credentials should win")
    }

    test("two services do not see each other") {
        let mine = scratchKeychain()
        let theirs = scratchKeychain()
        defer { mine.clear(); theirs.clear() }

        try mine.save(Keychain.Credentials(token: "mine", accountId: "1"))
        expect(theirs.load() == nil, "another service should not see it")
        expect(mine.load()?.token == "mine", "and mine should still be there")
    }

    test("a token with awkward characters survives the round trip") {
        let keychain = scratchKeychain()
        defer { keychain.clear() }
        let token = "ä 🔑 / \" \\ \n end"

        try keychain.save(Keychain.Credentials(token: token, accountId: "12345"))
        expect(keychain.load()?.token == token, "the token is stored as bytes, not as a name")
    }
}
