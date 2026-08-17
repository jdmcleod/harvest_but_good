import AppKit
import SwiftUI

/// Says what this build came from and what has landed since, on request.
///
/// Checks only when asked. An unprompted check would either nag or fail
/// quietly, and neither is worth spending someone's rate limit on.
struct UpdatesCard: View {
    /// Injectable so a preview or a test can stand one in; the app takes the
    /// real one, which reaches GitHub and tracks the branch this was built on.
    var checker = UpdateChecker(for: .current)
    var build: BuildInfo = .current
    /// Nil when the build carries no repo stamp or the repo is gone, which
    /// hides the Update Now button and leaves the command to run by hand.
    var updater: SelfUpdater? = SelfUpdater(build: .current)

    @State private var checking = false
    @State private var status: UpdateStatus?
    @State private var failure: String?
    /// Commits on main the tracked branch has not merged; nil until a check
    /// answers, and never set when the build tracks main itself.
    @State private var unmergedMain: Int?
    @State private var updating = false
    /// Set only when the update process ends with the app still running: a
    /// failure, or a success that had no app under this name to quit.
    @State private var updateOutcome: SelfUpdater.Outcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(Color.harvest)
                    .frame(width: 24, height: 24)
                Text("Updates")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(build.summary)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Button {
                        Task { await check() }
                    } label: {
                        if checking {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Check for Updates")
                        }
                    }
                    .disabled(checking || updating || build.commit == nil)

                    result
                }

                if let unmergedMain {
                    mainline(unmerged: unmergedMain)
                }

                if updateAvailable {
                    catchUp
                }
            }
            .padding(.leading, 32)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private var result: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            switch status {
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .behind(let commits):
                Label(
                    "\(commits) commit\(commits == 1 ? "" : "s") behind",
                    systemImage: "arrow.down.circle.fill"
                )
                .foregroundStyle(Color.harvest)
            case .offBranch(let behind):
                // Built from a branch of its own, so "behind" would be a lie
                // even when the branch does hold commits this build lacks.
                Label(
                    behind == 0
                        ? "Ahead of \(checker.branch) — nothing to update to"
                        : "Off \(checker.branch), which has \(behind) commit\(behind == 1 ? "" : "s") you don't",
                    systemImage: "arrow.triangle.branch"
                )
                .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }
        }
    }

    /// There is something to update to when the branch has moved past this
    /// build, or when main holds commits the staging branch should be rebased
    /// onto -- the update runs for either.
    private var updateAvailable: Bool {
        if case .behind = status { return true }
        return (unmergedMain ?? 0) > 0
    }

    /// Shown only when there is something to catch up to.
    private var catchUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let updater {
                updateNow(updater)
            }

            Text(updater == nil
                ? "Run this in the repo, then quit and reopen the app:"
                : "Or run it yourself in the repo:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(SelfUpdater.manualCommand(for: build))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.06))
                    )
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SelfUpdater.manualCommand(for: build), forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.plain)
                .pointingCursor()
                .help("Copy the command")

                if let commit = build.commit, let url = checker.changesURL(since: commit) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("See what changed", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .pointingCursor()
                }
            }
        }
    }

    /// The one-click path: pull and rebuild in the repo this was built from.
    /// On success the script quits this app and opens the new build, so the
    /// spinner's natural end is the window disappearing.
    private func updateNow(_ updater: SelfUpdater) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    startUpdate(updater)
                } label: {
                    if updating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Update Now")
                    }
                }
                .disabled(updating)

                if updating {
                    Text("Updating — the app will quit and reopen itself.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let updateOutcome {
                if updateOutcome.succeeded {
                    Label("Updated — quit and reopen the app.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Update failed. The log is at \(updater.logURL.path).", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    if !updateOutcome.detail.isEmpty {
                        Text(updateOutcome.detail)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func startUpdate(_ updater: SelfUpdater) {
        updating = true
        updateOutcome = nil
        do {
            try updater.start { outcome in
                updating = false
                updateOutcome = outcome
            }
        } catch {
            updating = false
            updateOutcome = SelfUpdater.Outcome(
                succeeded: false,
                detail: error.localizedDescription
            )
        }
    }

    /// Where the tracked branch stands against main, for builds off a staging
    /// branch. Its remedy is a merge rather than a pull, so it gets its own
    /// line instead of a place in the update status.
    private func mainline(unmerged: Int) -> some View {
        HStack(spacing: 8) {
            Label(
                unmerged == 0
                    ? "Everything on \(UpdateChecker.defaultBranch) is merged in"
                    : "\(UpdateChecker.defaultBranch) has \(unmerged) commit\(unmerged == 1 ? "" : "s") not merged into \(checker.branch)",
                systemImage: "arrow.triangle.merge"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            if unmerged > 0, let url = checker.mainlineChangesURL() {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("See what's on \(UpdateChecker.defaultBranch)", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .pointingCursor()
            }
        }
    }

    private func check() async {
        checking = true
        // Clear everything, so a second check never shows last time's answer
        // beside this time's error.
        status = nil
        failure = nil
        unmergedMain = nil
        updateOutcome = nil
        defer { checking = false }
        do {
            status = try await checker.status(of: build)
            unmergedMain = try await checker.unmergedMainlineCount()
        } catch {
            failure = error.localizedDescription
        }
    }
}
