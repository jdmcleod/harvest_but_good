import Foundation

enum ReleaseInstallError: LocalizedError {
    case notInstalled(URL)
    case tool(String, String)
    case unsigned(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let url):
            return "Running from \(url.path), not an app bundle, so there is nothing to replace."
        case .tool(let name, let output):
            return "\(name) failed: \(output)"
        case .unsigned(let output):
            return "The download isn't signed by RoleModel, so it was not installed. \(output)"
        }
    }
}

/// Replaces the running app with a release and relaunches it.
///
/// Downloads and checks everything while the app is still running, so a
/// failure is an error message rather than an app that quit and never came
/// back. Only the swap itself happens after quitting, in a script that
/// outlives the app.
public struct ReleaseInstaller {
    /// RoleModel's Apple team. The Keychain trusts builds signed by this team,
    /// which is what lets a release update without asking for a password.
    static let teamID = "4UDYMLGB25"

    /// What a download must satisfy before it replaces anything: Apple-issued,
    /// this app, and RoleModel's team. A tampered or foreign zip fails here.
    static let requirement = """
        anchor apple generic and identifier "com.rolemodel.HarvestTimer" \
        and certificate leaf[subject.OU] = "\(teamID)"
        """

    let app: URL
    let session: URLSession

    public init(app: URL = Bundle.main.bundleURL, session: URLSession = .shared) {
        self.app = app
        self.session = session
    }

    /// Returns once the swap is handed off; the caller then quits the app.
    public func install(_ release: Release) async throws {
        guard app.pathExtension == "app" else { throw ReleaseInstallError.notInstalled(app) }

        let stage = FileManager.default.temporaryDirectory
            .appendingPathComponent("HarvestButGood-\(release.version)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)

        do {
            let (zip, response) = try await session.download(from: release.download)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200 else {
                throw ReleaseInstallError.tool("Download", "GitHub returned \(code)")
            }
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, stage.path])
            // The zip's name, not the running bundle's, which Finder lets
            // anyone rename.
            let fresh = stage.appendingPathComponent("HarvestButGood.app")
            do {
                try run("/usr/bin/codesign", ["--verify", "--strict", "-R=\(Self.requirement)", fresh.path])
            } catch ReleaseInstallError.tool(_, let output) {
                throw ReleaseInstallError.unsigned(output)
            }
            try handOff(fresh, stage: stage)
        } catch {
            try? FileManager.default.removeItem(at: stage)
            throw error
        }
    }

    /// Copies beside the old bundle and swaps by renaming, keeping the old one
    /// until the new one is in place, then reopens whichever app is there.
    /// Leftovers from an interrupted run go first: ditto merges into an
    /// existing folder, and stale files would break the new signature.
    /// Same steps as Scripts/install-release.sh.
    private static let swapScript = """
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$APP.updating" "$APP.old"
        if ditto "$NEW" "$APP.updating" && mv "$APP" "$APP.old"; then
            if mv "$APP.updating" "$APP"; then
                rm -rf "$APP.old"
            else
                mv "$APP.old" "$APP"
            fi
        fi
        rm -rf "$STAGE" "$APP.updating"
        open "$APP"
        """

    private func handOff(_ fresh: URL, stage: URL) throws {
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", Self.swapScript]
        swap.environment = [
            "PATH": "/usr/bin:/bin",
            "PID": String(ProcessInfo.processInfo.processIdentifier),
            "NEW": fresh.path,
            "APP": app.path,
            "STAGE": stage.path,
        ]
        try swap.run()
    }

    private func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        // Read before waiting: a tool that fills the pipe blocks until
        // someone reads it, and would never exit.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ReleaseInstallError.tool(
                URL(fileURLWithPath: tool).lastPathComponent,
                text.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}
