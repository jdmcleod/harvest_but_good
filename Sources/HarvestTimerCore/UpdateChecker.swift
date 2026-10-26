import Foundation

/// Where this build stands against the branch it came from.
public enum UpdateStatus: Equatable, Sendable {
    /// Nothing has landed on the branch since this build.
    case upToDate
    /// This many commits have landed since this build.
    case behind(commits: Int)
    /// This build is not an ancestor of the branch: built from a branch of its
    /// own, or from a commit that was rebased away. `behind` counts what the
    /// branch holds that this build does not, which is zero when this build is
    /// simply further along.
    case offBranch(behind: Int)
}

enum UpdateCheckError: LocalizedError {
    case notStamped
    case unknownCommit
    case noRelease
    case rateLimited
    case http(Int, String)
    case network(Error)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .notStamped:
            return "This build carries no commit stamp, so there is nothing to compare. Rebuild with Scripts/build-app.sh."
        case .unknownCommit:
            // Also what a commit pushed seconds ago looks like: the API trails
            // the push by a moment, so this is worth retrying before believing.
            return "GitHub doesn't know the commit this was built from yet. If it was just pushed, try again in a moment."
        case .noRelease:
            return "No release has been published yet."
        case .rateLimited:
            return "GitHub is rate limiting this address. Try again in an hour."
        case .http(let code, let body):
            return "GitHub returned \(code): \(body)"
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .malformed(let detail):
            return "Couldn't read GitHub's answer: \(detail)"
        }
    }
}

/// A published release, as much of it as updating needs.
public struct Release: Equatable, Sendable {
    public let version: String
    /// The zipped app attached to the release.
    public let download: URL
    /// The release page, for reading the notes.
    public let page: URL

    /// The asset the release workflow attaches. Named without the version so
    /// releases/latest/download/ always finds it.
    static let assetName = "HarvestButGood.zip"

    /// Compares numerically, so 0.10.0 is newer than 0.9.0.
    public func isNewer(than version: String) -> Bool {
        self.version.compare(version, options: .numeric) == .orderedDescending
    }
}

/// Asks GitHub what has landed since a build was made: commits on the branch
/// for a build from a checkout, or the latest release for a release build.
///
/// Reads only. A checkout build gets a sentence and a command to run, since
/// its Keychain access is pinned to its own certificate and a release would
/// not pass. `ReleaseInstaller` does the installing.
public struct UpdateChecker {
    public static let defaultRepository = "jdmcleod/harvest_but_good"
    public static let defaultBranch = "main"

    let repository: String
    let branch: String
    /// The shared session in the app. Tests hand in one backed by a stub.
    let session: URLSession

    public init(
        repository: String = UpdateChecker.defaultRepository,
        branch: String = UpdateChecker.defaultBranch,
        session: URLSession = .shared
    ) {
        self.repository = repository
        self.branch = branch
        self.session = session
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// GitHub reports the comparison from the head's point of view, so with the
    /// build as base and the branch as head, "ahead" means the branch has moved
    /// on and this build has not.
    private struct Comparison: Decodable {
        let status: String
        let aheadBy: Int
        let behindBy: Int
    }

    public func status(of build: BuildInfo) async throws -> UpdateStatus {
        guard let commit = build.commit else { throw UpdateCheckError.notStamped }
        let comparison = try await get(
            "compare/\(commit)...\(branch)", as: Comparison.self, notFound: .unknownCommit
        )
        switch comparison.status {
        case "identical":
            return .upToDate
        case "ahead":
            return .behind(commits: comparison.aheadBy)
        case "behind":
            return .offBranch(behind: 0)
        case "diverged":
            return .offBranch(behind: comparison.aheadBy)
        default:
            throw UpdateCheckError.malformed("unexpected status \"\(comparison.status)\"")
        }
    }

    /// Where to send someone who wants to read the commits themselves.
    public func changesURL(since commit: String) -> URL? {
        URL(string: "https://github.com/\(repository)/compare/\(commit)...\(branch)")
    }

    /// What to run to catch up. The app builds and installs itself in one step,
    /// so this is the whole of it.
    public static let updateCommand = "git pull && Scripts/build-app.sh"

    private struct LatestRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadUrl: URL
        }
        let tagName: String
        let htmlUrl: URL
        let assets: [Asset]
    }

    /// The newest published release. Drafts and pre-releases never show here,
    /// which is GitHub's rule for releases/latest.
    public func latestRelease() async throws -> Release {
        let latest = try await get("releases/latest", as: LatestRelease.self, notFound: .noRelease)
        guard let asset = latest.assets.first(where: { $0.name == Release.assetName }) else {
            throw UpdateCheckError.malformed("\(latest.tagName) has no \(Release.assetName)")
        }
        return Release(
            version: latest.tagName.hasPrefix("v") ? String(latest.tagName.dropFirst()) : latest.tagName,
            download: asset.browserDownloadUrl,
            page: latest.htmlUrl
        )
    }

    /// The two calls mean different things by a 404, so each names its own.
    private func get<T: Decodable>(
        _ path: String, as type: T.Type, notFound: UpdateCheckError
    ) async throws -> T {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/\(path)") else {
            throw UpdateCheckError.malformed("could not build a URL for \(repository)")
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub turns away anonymous requests that name no client.
        request.setValue("HarvestButGood", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw UpdateCheckError.network(error)
        }

        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            // A public repo needs no token, so the interesting failures are a
            // commit GitHub has never seen and the anonymous rate limit.
            if code == 404 { throw notFound }
            if code == 403 || code == 429 { throw UpdateCheckError.rateLimited }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UpdateCheckError.http(code, String(body.prefix(200)))
        }

        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw UpdateCheckError.malformed(error.localizedDescription)
        }
    }
}
