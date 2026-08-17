import Foundation

/// Runs the update command in the repo this build came from and reports how
/// it ended. On success the command quits this app and relaunches the new
/// build, so silence is the good outcome: a report only arrives when the
/// process ends while the app is still here to hear it.
public struct SelfUpdater {
    /// A mainline build only ever moves forward, so updating is a fast-forward
    /// pull and a rebuild. --ff-only so a conflicted pull fails with a clear
    /// message instead of starting a merge that nothing is attending.
    public static let mainlineCommand = "git pull --ff-only && Scripts/build-app.sh"

    /// A staging branch rides on top of main: sync the branch, replay it onto
    /// the latest main, and push the result back. The push is not optional --
    /// a rebase rewrites the branch, the update check reads GitHub's copy, and
    /// leaving the two apart turns every later answer into nonsense.
    /// --force-with-lease because a rebase always needs force, while still
    /// refusing to overwrite commits that have not been fetched here.
    public static let stagingCommand = "git pull --ff-only"
        + " && git rebase origin/\(UpdateChecker.defaultBranch)"
        + " && git push --force-with-lease origin HEAD"
        + " && Scripts/build-app.sh"

    /// The staging command plus the guard an unattended run needs: a rebase
    /// that hits conflicts is aborted, leaving the repo exactly as it was,
    /// rather than left mid-rebase with no one at the keyboard.
    static let stagingScript = """
        set -euo pipefail
        git pull --ff-only
        if ! git rebase origin/\(UpdateChecker.defaultBranch); then
            git rebase --abort 2>/dev/null || true
            echo "Rebasing onto origin/\(UpdateChecker.defaultBranch) hit conflicts;" \
                "the branch was left as it was. Bring \(UpdateChecker.defaultBranch) in by hand."
            exit 1
        fi
        git push --force-with-lease origin HEAD
        Scripts/build-app.sh
        """

    /// What someone running the update by hand should paste: the same steps
    /// the button runs, minus the abort guard a terminal user is there to be.
    public static func manualCommand(for build: BuildInfo) -> String {
        onMainline(build) ? mainlineCommand : stagingCommand
    }

    /// An unstamped branch is treated as the mainline: with no branch to ride
    /// on top of main, rebasing would be a guess.
    static func onMainline(_ build: BuildInfo) -> Bool {
        (build.branch ?? UpdateChecker.defaultBranch) == UpdateChecker.defaultBranch
    }

    /// Where the update writes its output, kept when it fails so there is
    /// something to read. Under ~/Library/Logs, where Console.app looks.
    public static let defaultLogURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/HarvestButGood/update.log")

    public let repo: URL
    /// What actually runs in the repo. Tests substitute something git-free.
    let script: String
    let logURL: URL

    /// Nil when the build carries no repo stamp or the repo has moved since:
    /// there is nowhere to run the update, so there should be no button.
    public init?(build: BuildInfo) {
        guard let path = build.repoPath,
              FileManager.default.fileExists(atPath: path)
        else { return nil }
        self.init(
            repo: URL(fileURLWithPath: path),
            script: Self.onMainline(build) ? Self.mainlineCommand : Self.stagingScript
        )
    }

    init(repo: URL, script: String, logURL: URL = SelfUpdater.defaultLogURL) {
        self.repo = repo
        self.script = script
        self.logURL = logURL
    }

    public struct Outcome: Equatable, Sendable {
        public let succeeded: Bool
        /// The end of the log, where a pull or build failure says why.
        public let detail: String
    }

    /// Starts the update and returns; the command owns everything after that.
    /// `onExit` arrives on the main queue only when the process ends with this
    /// app still running: a failure, or a success that had no app to quit
    /// (a dev copy running under another process name).
    ///
    /// Output goes to a file rather than a pipe on purpose. A pipe's far end
    /// dies with this app, and writing to a dead pipe would kill the update at
    /// the very moment it starts working.
    public func start(onExit: @escaping (Outcome) -> Void) throws {
        let log = try openedLog()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.currentDirectoryURL = repo
        process.standardOutput = log
        process.standardError = log
        let logURL = logURL
        process.terminationHandler = { finished in
            try? log.close()
            let outcome = Outcome(
                succeeded: finished.terminationStatus == 0,
                detail: Self.tail(of: logURL)
            )
            DispatchQueue.main.async { onExit(outcome) }
        }
        try process.run()
    }

    /// A fresh log per attempt: last time's failure explains nothing about
    /// this time's.
    private func openedLog() throws -> FileHandle {
        let fm = FileManager.default
        try fm.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        fm.createFile(atPath: logURL.path, contents: nil)
        return try FileHandle(forWritingTo: logURL)
    }

    /// The last few non-empty lines of the log, which is where a failed pull
    /// or build states its reason.
    static func tail(of url: URL, lines: Int = 3) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(lines)
            .joined(separator: "\n")
    }
}
