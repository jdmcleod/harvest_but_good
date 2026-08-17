import Foundation
import Testing

@testable import HarvestTimerCore

/// GitHub's compare reply, trimmed to the fields the checker reads.
private func comparison(_ status: String, ahead: Int = 0, behind: Int = 0) -> String {
    """
    {"status": "\(status)", "ahead_by": \(ahead), "behind_by": \(behind),
     "total_commits": \(ahead), "commits": []}
    """
}

private let stampedBuild = BuildInfo(commit: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0", isDirty: false)

private func checker(
    _ replies: [StubHarvestServer.Reply],
    branch: String = "main"
) -> (UpdateChecker, StubHarvestServer) {
    let server = StubHarvestServer(replies)
    return (UpdateChecker(repository: "owner/repo", branch: branch, session: server.session()), server)
}

@Test("Checking for updates")
func runUpdateCheckerTests() async {
    await test("an identical comparison is up to date") {
        let (checker, _) = checker([.json(comparison("identical"))])
        expect(try await checker.status(of: stampedBuild) == .upToDate, "expected up to date")
    }

    await test("commits on the branch since this build count as behind") {
        let (checker, _) = checker([.json(comparison("ahead", ahead: 3))])
        let status = try await checker.status(of: stampedBuild)
        expect(status == .behind(commits: 3), "expected 3 behind, got \(status)")
    }

    await test("one commit behind, so a view can drop the plural") {
        let (checker, _) = checker([.json(comparison("ahead", ahead: 1))])
        expect(try await checker.status(of: stampedBuild) == .behind(commits: 1), "expected 1 behind")
    }

    await test("a build further along than the branch is off it, with nothing to fetch") {
        let (checker, _) = checker([.json(comparison("behind", behind: 2))])
        let status = try await checker.status(of: stampedBuild)
        expect(status == .offBranch(behind: 0), "expected off-branch with nothing behind, got \(status)")
    }

    await test("a diverged build reports what the branch holds that it does not") {
        let (checker, _) = checker([.json(comparison("diverged", ahead: 4, behind: 2))])
        let status = try await checker.status(of: stampedBuild)
        expect(status == .offBranch(behind: 4), "expected off-branch behind 4, got \(status)")
    }

    await test("the request asks GitHub to compare this build against the branch") {
        let (checker, server) = checker([.json(comparison("identical"))])
        _ = try await checker.status(of: stampedBuild)
        let sent = server.requests.first
        expect(server.callCount == 1, "expected one call, got \(server.callCount)")
        expect(
            sent?.path == "/repos/owner/repo/compare/\(stampedBuild.commit!)...main",
            "expected a compare path, got \(sent?.path ?? "none")"
        )
        expect(sent?.header("Accept") == "application/vnd.github+json", "expected GitHub's media type")
        expect(sent?.header("User-Agent") == "HarvestButGood", "anonymous requests must name a client")
    }

    await test("an unstamped build never reaches the network") {
        let (checker, server) = checker([.json(comparison("identical"))])
        await expectFailure(
            "notStamped",
            containing: "no commit stamp",
            try await checker.status(of: BuildInfo(commit: nil, isDirty: false))
        )
        expect(server.callCount == 0, "there is nothing to ask about, so nothing should be asked")
    }

    // A commit pushed seconds ago 404s too, because the API trails the push, so
    // the message has to leave room for a retry rather than blame the user.
    await test("a commit GitHub has not seen says so, and suggests trying again") {
        let (checker, _) = checker([.status(404, body: "{}")])
        await expectFailure(
            "unknownCommit",
            containing: "try again in a moment",
            try await checker.status(of: stampedBuild)
        )
    }

    await test("the anonymous rate limit is called by its name") {
        for code in [403, 429] {
            let (checker, _) = checker([.status(code, body: "{}")])
            await expectFailure(
                "rateLimited on \(code)",
                containing: "rate limiting",
                try await checker.status(of: stampedBuild)
            )
        }
    }

    await test("any other status carries the code back") {
        let (checker, _) = checker([.status(500, body: "boom")])
        await expectFailure("http", containing: "500", try await checker.status(of: stampedBuild))
    }

    await test("an unexpected status is not guessed at") {
        let (checker, _) = checker([.json(comparison("sideways"))])
        await expectFailure("malformed", containing: "sideways", try await checker.status(of: stampedBuild))
    }

    await test("a reply that isn't the expected shape is reported, not crashed on") {
        let (checker, _) = checker([.json(#"{"unexpected": true}"#)])
        await expectFailure("malformed", containing: "Couldn't read", try await checker.status(of: stampedBuild))
    }

    await test("a network failure is passed along") {
        let (checker, _) = checker([.failure(.notConnectedToInternet)])
        await expectFailure("network", containing: "Network error", try await checker.status(of: stampedBuild))
    }

    await test("the changes link points at the comparison on github.com") {
        let (checker, _) = checker([])
        let url = checker.changesURL(since: "abc123")
        expect(
            url?.absoluteString == "https://github.com/owner/repo/compare/abc123...main",
            "expected a compare page, got \(url?.absoluteString ?? "none")"
        )
    }
}

@Test("Tracking the branch a build came from")
func runBranchTrackingTests() async {
    await test("a checker built for a stamped build compares against its branch") {
        let server = StubHarvestServer([.json(comparison("identical"))])
        let build = BuildInfo(commit: "abc123", branch: "staging", isDirty: false)
        let checker = UpdateChecker(for: build, session: server.session())
        _ = try await checker.status(of: build)
        expect(
            server.requests.first?.path.hasSuffix("/compare/abc123...staging") == true,
            "expected a compare against staging, got \(server.requests.first?.path ?? "none")"
        )
    }

    await test("a build with no branch stamp falls back to main") {
        let build = BuildInfo(commit: "abc123", branch: nil, isDirty: false)
        let checker = UpdateChecker(for: build)
        expect(checker.branch == "main", "expected the mainline, got \(checker.branch)")
    }
}

@Test("What main holds that a staging branch has not merged")
func runUnmergedMainlineTests() async {
    await test("tracking main itself, there is no question to ask and no call made") {
        let (checker, server) = checker([.json(comparison("identical"))])
        let count = try await checker.unmergedMainlineCount()
        expect(count == nil, "expected nil, got \(String(describing: count))")
        expect(server.callCount == 0, "main against main is not worth a request")
    }

    await test("the request compares the branch as base against main as head") {
        let (checker, server) = checker([.json(comparison("identical"))], branch: "staging")
        _ = try await checker.unmergedMainlineCount()
        expect(
            server.requests.first?.path == "/repos/owner/repo/compare/staging...main",
            "expected staging...main, got \(server.requests.first?.path ?? "none")"
        )
    }

    await test("identical branches have nothing unmerged") {
        let (checker, _) = checker([.json(comparison("identical"))], branch: "staging")
        expect(try await checker.unmergedMainlineCount() == 0, "expected 0")
    }

    await test("a branch holding everything main does and more has nothing unmerged") {
        let (checker, _) = checker([.json(comparison("behind", behind: 3))], branch: "staging")
        expect(try await checker.unmergedMainlineCount() == 0, "expected 0")
    }

    await test("commits on main the branch lacks are counted") {
        let (checker, _) = checker([.json(comparison("ahead", ahead: 5))], branch: "staging")
        expect(try await checker.unmergedMainlineCount() == 5, "expected 5")
    }

    await test("a diverged branch counts only what main has that it does not") {
        let (checker, _) = checker([.json(comparison("diverged", ahead: 2, behind: 7))], branch: "staging")
        expect(try await checker.unmergedMainlineCount() == 2, "expected 2")
    }

    await test("the mainline changes link compares the branch against main") {
        let (checker, _) = checker([], branch: "staging")
        expect(
            checker.mainlineChangesURL()?.absoluteString
                == "https://github.com/owner/repo/compare/staging...main",
            "got \(checker.mainlineChangesURL()?.absoluteString ?? "none")"
        )
    }
}

@Test("What a build knows about itself")
func runBuildInfoTests() {
    test("the stamps are read off Info.plist") {
        let build = BuildInfo(infoDictionary: ["GitCommit": "abcdef1234567890", "GitDirty": "false"])
        expect(build.commit == "abcdef1234567890", "expected the full commit")
        expect(build.shortCommit == "abcdef1", "expected git's own seven characters")
        expect(!build.isDirty, "\"false\" is not dirty")
        expect(build.summary == "Built from abcdef1.", "got \(build.summary)")
    }

    test("a dirty build says so, because it is not the commit it names") {
        let build = BuildInfo(infoDictionary: ["GitCommit": "abcdef1234567890", "GitDirty": "true"])
        expect(build.isDirty, "\"true\" is dirty")
        expect(build.summary.contains("never committed"), "got \(build.summary)")
    }

    test("a bundle with no stamps admits it rather than guessing") {
        for empty in [[:], ["GitCommit": ""], ["GitCommit": "   "]] as [[String: Any]] {
            let build = BuildInfo(infoDictionary: empty)
            expect(build.commit == nil, "expected no commit from \(empty)")
            expect(build.shortCommit == nil, "expected no short commit from \(empty)")
            expect(build.summary == "This build carries no commit stamp.", "got \(build.summary)")
        }
    }

    test("anything but \"true\" is clean, so a missing stamp is not alarming") {
        let build = BuildInfo(infoDictionary: ["GitCommit": "abc1234"])
        expect(!build.isDirty, "absent means clean")
    }

    test("a branch stamp names the branch in the summary") {
        let build = BuildInfo(infoDictionary: [
            "GitCommit": "abcdef1234567890", "GitBranch": "staging", "GitDirty": "false",
        ])
        expect(build.branch == "staging", "expected the branch stamp")
        expect(build.summary == "Built from abcdef1 on staging.", "got \(build.summary)")
    }

    test("the repo path stamp is read, and an empty one means none") {
        let stamped = BuildInfo(infoDictionary: [
            "GitCommit": "abc1234", "GitRepoPath": "/Users/someone/repo",
        ])
        expect(stamped.repoPath == "/Users/someone/repo", "expected the stamped path")
        let unstamped = BuildInfo(infoDictionary: ["GitCommit": "abc1234", "GitRepoPath": ""])
        expect(unstamped.repoPath == nil, "expected no path from an empty stamp")
    }

    test("an empty branch stamp is no branch at all, as a detached HEAD writes") {
        for empty in ["", "   "] {
            let build = BuildInfo(infoDictionary: ["GitCommit": "abc1234", "GitBranch": empty])
            expect(build.branch == nil, "expected no branch from \"\(empty)\"")
            expect(build.summary == "Built from abc1234.", "got \(build.summary)")
        }
    }
}

/// Runs `body`, expecting it to throw something whose message contains
/// `containing`. Named after the case so a failure says which one.
private func expectFailure<T>(
    _ name: String,
    containing: String,
    _ body: @autoclosure () async throws -> T,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        _ = try await body()
        expect(false, "\(name): expected a failure, got a value")
    } catch {
        let message = error.localizedDescription
        expect(
            message.contains(containing),
            "\(name): expected a message mentioning \"\(containing)\", got \"\(message)\""
        )
    }
}
