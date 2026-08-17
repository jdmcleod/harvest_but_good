import Foundation

/// What the running app was built from. `Scripts/build-app.sh` stamps these
/// into Info.plist; a bundle put together some other way carries neither, and
/// this says so rather than inventing an answer.
public struct BuildInfo: Equatable, Sendable {
    /// The commit the bundle was built at, or nil when nothing stamped one.
    public let commit: String?
    /// The branch the bundle was built from, or nil when nothing stamped one:
    /// an old bundle, a detached HEAD, or no build script at all. Update checks
    /// compare against this, so a build from a staging branch follows that
    /// branch instead of counting itself forever off main.
    public let branch: String?
    /// Where the repo the bundle was built from lived, so the app can run the
    /// update itself. The path was true at build time and only probably still
    /// is, so anyone acting on it checks the disk first.
    public let repoPath: String?
    /// Whether tracked files differed from that commit at build time. A dirty
    /// build is not the commit it names, so comparing against the commit tells
    /// you about the commit and not about what you are running.
    public let isDirty: Bool

    public init(commit: String?, branch: String? = nil, repoPath: String? = nil, isDirty: Bool) {
        // An absent key and an empty one mean the same thing to everyone
        // reading this, so they are flattened here rather than at each use.
        self.commit = Self.flatten(commit)
        self.branch = Self.flatten(branch)
        self.repoPath = Self.flatten(repoPath)
        self.isDirty = isDirty
    }

    private static func flatten(_ stamp: String?) -> String? {
        let trimmed = stamp?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// What this copy of the app was built from.
    public static let current = BuildInfo(infoDictionary: Bundle.main.infoDictionary ?? [:])

    /// Reads the stamps out of an Info.plist. Takes the dictionary rather than
    /// the bundle so a test can hand over one it wrote itself.
    init(infoDictionary: [String: Any]) {
        self.init(
            commit: infoDictionary["GitCommit"] as? String,
            branch: infoDictionary["GitBranch"] as? String,
            repoPath: infoDictionary["GitRepoPath"] as? String,
            // Written as a string because the build script assembles the plist
            // by hand, where "true" is easier to get right than <true/>.
            isDirty: (infoDictionary["GitDirty"] as? String) == "true"
        )
    }

    /// The seven characters git itself abbreviates a commit to.
    public var shortCommit: String? {
        commit.map { String($0.prefix(7)) }
    }

    /// How to describe this build in a sentence, for a view that wants to say
    /// where it came from before saying what is newer.
    public var summary: String {
        guard let shortCommit else { return "This build carries no commit stamp." }
        let origin = branch.map { "\(shortCommit) on \($0)" } ?? shortCommit
        return isDirty
            ? "Built from \(origin), plus changes that were never committed."
            : "Built from \(origin)."
    }
}
