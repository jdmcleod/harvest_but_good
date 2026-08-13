import AppKit
import SwiftUI

/// Says what this build came from and what has landed since, on request.
///
/// Checks only when asked. An unprompted check would either nag or fail
/// quietly, and neither is worth spending someone's rate limit on.
struct UpdatesCard: View {
    /// Injectable so a preview or a test can stand one in; the app takes the
    /// real one, which reaches GitHub.
    var checker = UpdateChecker()
    var build: BuildInfo = .current

    @State private var checking = false
    @State private var status: UpdateStatus?
    @State private var failure: String?

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
                    .disabled(checking || build.commit == nil)

                    result
                }

                if case .behind = status {
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

    /// Shown only when there is something to catch up to.
    private var catchUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Run this in the repo, then quit and reopen the app:")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(UpdateChecker.updateCommand)
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
                    NSPasteboard.general.setString(UpdateChecker.updateCommand, forType: .string)
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

    private func check() async {
        checking = true
        // Clear both, so a second check never shows last time's answer beside
        // this time's error.
        status = nil
        failure = nil
        defer { checking = false }
        do {
            status = try await checker.status(of: build)
        } catch {
            failure = error.localizedDescription
        }
    }
}
