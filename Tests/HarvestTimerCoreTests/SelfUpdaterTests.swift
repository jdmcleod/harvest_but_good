import Foundation
import Testing

@testable import HarvestTimerCore

/// A scratch directory posing as the repo, plus a log path inside it so a
/// test never writes to the real ~/Library/Logs.
private func scratch() throws -> (repo: URL, log: URL) {
    let repo = FileManager.default.temporaryDirectory
        .appendingPathComponent("SelfUpdaterTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
    return (repo, repo.appendingPathComponent("update.log"))
}

/// Runs `script` in a scratch repo and waits for the outcome a real update
/// would deliver, exercising the process plumbing without touching git.
private func outcome(of script: String) async throws -> SelfUpdater.Outcome {
    let (repo, log) = try scratch()
    defer { try? FileManager.default.removeItem(at: repo) }
    let updater = SelfUpdater(repo: repo, script: script, logURL: log)
    return try await withCheckedThrowingContinuation { continuation in
        do {
            try updater.start { continuation.resume(returning: $0) }
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

@Test("Updating the app in place")
func runSelfUpdaterTests() async {
    test("a build with no repo stamp offers no updater") {
        let build = BuildInfo(commit: "abc1234", isDirty: false)
        expect(SelfUpdater(build: build) == nil, "nowhere to run, so no updater")
    }

    test("a repo that has moved since the build offers no updater") {
        let build = BuildInfo(
            commit: "abc1234",
            repoPath: "/nowhere/that/exists",
            isDirty: false
        )
        expect(SelfUpdater(build: build) == nil, "a gone repo is nowhere to run")
    }

    test("a stamped build whose repo still exists gets an updater at that repo") {
        let (repo, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: repo) }
        let build = BuildInfo(commit: "abc1234", repoPath: repo.path, isDirty: false)
        let updater = SelfUpdater(build: build)
        expect(updater?.repo.path == repo.path, "expected the stamped repo")
        expect(
            updater?.script == SelfUpdater.mainlineCommand,
            "with no branch stamp there is nothing to rebase, so fast-forward only"
        )
    }

    test("a staging-branch build updates by rebasing onto main, with the abort guard") {
        let (repo, _) = try scratch()
        defer { try? FileManager.default.removeItem(at: repo) }
        let build = BuildInfo(
            commit: "abc1234", branch: "staging", repoPath: repo.path, isDirty: false
        )
        let updater = SelfUpdater(build: build)
        expect(updater?.script == SelfUpdater.stagingScript, "expected the guarded staging script")
    }

    test("the staging steps rebase onto main and push the rewritten branch back") {
        for steps in [SelfUpdater.stagingCommand, SelfUpdater.stagingScript] {
            expect(steps.contains("git pull --ff-only"), "the branch syncs first")
            expect(steps.contains("git rebase origin/main"), "expected the rebase")
            expect(
                steps.contains("git push --force-with-lease origin HEAD"),
                "a kept-local rebase would desync the copy the update check reads"
            )
            expect(steps.contains("Scripts/build-app.sh"), "it ends by rebuilding")
        }
        expect(
            SelfUpdater.stagingScript.contains("git rebase --abort"),
            "an unattended conflict must be aborted, not left half-done"
        )
    }

    test("what to paste matches the branch the build tracks") {
        let mainline = BuildInfo(commit: "abc", branch: "main", isDirty: false)
        let unstamped = BuildInfo(commit: "abc", isDirty: false)
        let staging = BuildInfo(commit: "abc", branch: "staging", isDirty: false)
        expect(
            SelfUpdater.manualCommand(for: mainline) == SelfUpdater.mainlineCommand,
            "a main build fast-forwards"
        )
        expect(
            SelfUpdater.manualCommand(for: unstamped) == SelfUpdater.mainlineCommand,
            "no branch stamp means nothing to rebase"
        )
        expect(
            SelfUpdater.manualCommand(for: staging) == SelfUpdater.stagingCommand,
            "a staging build rebases onto main"
        )
    }

    await test("a command that fails reports failure with the log's last words") {
        let result = try await outcome(of: "echo starting; echo 'fatal: no merge' >&2; exit 3")
        expect(!result.succeeded, "exit 3 is a failure")
        expect(result.detail.contains("fatal: no merge"), "expected the reason, got \(result.detail)")
    }

    await test("the command runs in the repo directory") {
        let result = try await outcome(of: "test -f update.log && exit 0 || exit 1")
        // The log lives inside the scratch repo, so seeing it proves the cwd.
        expect(result.succeeded, "expected the command to find itself in the repo")
    }

    await test("a command that succeeds with the app still alive says so") {
        let result = try await outcome(of: "echo done")
        expect(result.succeeded, "exit 0 is a success")
    }

    await test("the staging script runs pull, rebase, push, build, in that order") {
        let result = try await stagedOutcome(rebaseConflicts: false)
        expect(result.outcome.succeeded, "every step passing is a success: \(result.outcome.detail)")
        expect(
            result.gitCalls == ["pull --ff-only", "rebase origin/main", "push --force-with-lease origin HEAD"],
            "got \(result.gitCalls)"
        )
        expect(result.outcome.detail.contains("built"), "the build script should have run last")
    }

    await test("a conflicted rebase is aborted and reported, and nothing further runs") {
        let result = try await stagedOutcome(rebaseConflicts: true)
        expect(!result.outcome.succeeded, "a conflict is a failure")
        expect(result.outcome.detail.contains("hit conflicts"), "got \(result.outcome.detail)")
        expect(
            result.gitCalls == ["pull --ff-only", "rebase origin/main", "rebase --abort"],
            "no push and no build after a conflict; got \(result.gitCalls)"
        )
    }

    test("the tail keeps only the last non-empty lines") {
        let detail = SelfUpdater.tail(of: writtenLog("one\ntwo\n\n  \nthree\nfour\nfive\n"))
        expect(detail == "three\nfour\nfive", "got \(detail)")
    }

    test("an unreadable log tails to nothing rather than failing") {
        let missing = URL(fileURLWithPath: "/nowhere/update.log")
        expect(SelfUpdater.tail(of: missing) == "", "expected an empty tail")
    }
}

/// Runs the real staging script in a scratch repo whose `git` is a stub, so
/// the guard's behavior is exercised without a real repo or network. The stub
/// records each call and fails the rebase when asked to, as a conflict would.
private func stagedOutcome(
    rebaseConflicts: Bool
) async throws -> (outcome: SelfUpdater.Outcome, gitCalls: [String]) {
    let (repo, log) = try scratch()
    defer { try? FileManager.default.removeItem(at: repo) }
    let fm = FileManager.default

    let calls = repo.appendingPathComponent("git-calls")
    let stubGit = """
        #!/bin/bash
        echo "$@" >> "\(calls.path)"
        if [ "$1" = "rebase" ] && [ "$2" != "--abort" ]; then
            exit \(rebaseConflicts ? 1 : 0)
        fi
        exit 0
        """
    let bin = repo.appendingPathComponent("stub-bin")
    try fm.createDirectory(at: bin, withIntermediateDirectories: true)
    try stubGit.write(to: bin.appendingPathComponent("git"), atomically: true, encoding: .utf8)

    let scripts = repo.appendingPathComponent("Scripts")
    try fm.createDirectory(at: scripts, withIntermediateDirectories: true)
    try "#!/bin/bash\necho built"
        .write(to: scripts.appendingPathComponent("build-app.sh"), atomically: true, encoding: .utf8)
    for stub in [bin.appendingPathComponent("git"), scripts.appendingPathComponent("build-app.sh")] {
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
    }

    let script = "export PATH=\"\(bin.path)\":$PATH\n" + SelfUpdater.stagingScript
    let updater = SelfUpdater(repo: repo, script: script, logURL: log)
    let outcome: SelfUpdater.Outcome = try await withCheckedThrowingContinuation { continuation in
        do {
            try updater.start { continuation.resume(returning: $0) }
        } catch {
            continuation.resume(throwing: error)
        }
    }
    let recorded = (try? String(contentsOf: calls, encoding: .utf8)) ?? ""
    return (outcome, recorded.split(separator: "\n").map(String.init))
}

/// Writes `contents` to a scratch log file and hands back where it landed.
private func writtenLog(_ contents: String) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("SelfUpdaterTests-log-\(UUID().uuidString).log")
    try? contents.write(to: url, atomically: true, encoding: .utf8)
    return url
}
