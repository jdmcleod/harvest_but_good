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

private func checker(_ replies: [StubHarvestServer.Reply]) -> (UpdateChecker, StubHarvestServer) {
    let server = StubHarvestServer(replies)
    return (UpdateChecker(repository: "owner/repo", branch: "main", session: server.session()), server)
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

    await test("a commit GitHub has never seen says so") {
        let (checker, _) = checker([.status(404, body: "{}")])
        await expectFailure(
            "unknownCommit",
            containing: "never have been pushed",
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
