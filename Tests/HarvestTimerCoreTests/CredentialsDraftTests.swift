import Foundation
import Testing

@testable import HarvestTimerCore

@Test("Credentials draft")
@MainActor
func runCredentialsDraftTests() async {
    await test("a token Harvest accepts says who it belongs to") {
        let draft = CredentialsDraft(makeClient: { _ in FakeHarvest() })
        draft.token = "secret"
        draft.accountId = "999"
        await draft.validate()
        expect(
            draft.validation == .success("Connected as Ada Lovelace @ Test Co"),
            "got \(String(describing: draft.validation))"
        )
        expect(draft.canSave, "a checked pair should be savable")
    }

    await test("a token Harvest turns down can't be saved") {
        let fake = FakeHarvest()
        fake.failNextCall = FakeHarvest.FakeError.noSuchEntry
        let draft = CredentialsDraft(makeClient: { _ in fake })
        draft.token = "wrong"
        draft.accountId = "999"
        await draft.validate()
        guard case .failure = draft.validation else {
            expect(false, "expected a failure, got \(String(describing: draft.validation))")
            return
        }
        expect(!draft.canSave, "a refused pair should not be savable")
    }

    await test("editing after a check throws its answer away") {
        let draft = CredentialsDraft(makeClient: { _ in FakeHarvest() })
        draft.token = "secret"
        draft.accountId = "999"
        await draft.validate()
        draft.token = "secret2"
        expect(draft.validation == nil, "a new token hasn't been checked")
        expect(!draft.canSave, "so it can't be saved yet")
    }

    await test("the check and the save use the trimmed pair") {
        var checked: Keychain.Credentials?
        let draft = CredentialsDraft(makeClient: { credentials in
            checked = credentials
            return FakeHarvest()
        })
        draft.token = "  secret\n"
        draft.accountId = " 999 "
        await draft.validate()
        expect(
            checked == Keychain.Credentials(token: "secret", accountId: "999"),
            "got \(String(describing: checked))"
        )
    }

    test("there's nothing to check until both fields are filled") {
        let draft = CredentialsDraft(accountId: "999")
        expect(!draft.canValidate, "the token is missing")
        draft.token = "   "
        expect(!draft.canValidate, "blank space is not a token")
        draft.token = "secret"
        expect(draft.canValidate, "both are there now")
    }

    await test("saving hands the pair to the state") {
        try await withTemporaryDirectory { directory in
            let state = AppState(client: FakeHarvest(), storageDirectory: directory)
            defer { state.stop() }
            let draft = CredentialsDraft(makeClient: { _ in FakeHarvest() })
            draft.token = "secret"
            draft.accountId = "999"
            expect(!draft.save(into: state), "an unchecked pair should not save")

            await draft.validate()
            expect(draft.save(into: state), "a checked pair should save")
            expect(
                state.credentials == Keychain.Credentials(token: "secret", accountId: "999"),
                "got \(String(describing: state.credentials))"
            )
        }
    }
}
