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

/// Asks GitHub what has landed on the tracked branch since a build was made.
///
/// Reads rather than writes, and never downloads anything: the app cannot
/// replace itself safely while its Keychain access is pinned to one build's
/// hash, so the answer here is a sentence and a command to run, not an install.
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
        let comparison = try await compare(base: commit, head: branch)
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

    private func compare(base: String, head: String) async throws -> Comparison {
        guard let url = URL(
            string: "https://api.github.com/repos/\(repository)/compare/\(base)...\(head)"
        ) else {
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
            if code == 404 { throw UpdateCheckError.unknownCommit }
            if code == 403 || code == 429 { throw UpdateCheckError.rateLimited }
            let body = String(data: data, encoding: .utf8) ?? ""
            throw UpdateCheckError.http(code, String(body.prefix(200)))
        }

        do {
            return try Self.decoder.decode(Comparison.self, from: data)
        } catch {
            throw UpdateCheckError.malformed(error.localizedDescription)
        }
    }
}
