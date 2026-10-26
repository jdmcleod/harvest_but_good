import AppKit
import SwiftUI

/// The updates card for a release build: checks the latest GitHub release and
/// installs it in place. A build from a checkout gets `UpdatesCard` instead.
///
/// Checks only when asked, like `UpdatesCard`, and installs only when asked.
struct ReleaseUpdatesCard: View {
    @Environment(\.palette) private var palette
    let version: String
    var checker = UpdateChecker()
    var installer = ReleaseInstaller()

    @State private var busy = false
    @State private var latest: Release?
    @State private var failure: String?

    var body: some View {
        SettingsCard(title: "Updates", systemImage: "arrow.down.circle") {
            HStack(spacing: 12) {
                result
                Button {
                    Task { await check() }
                } label: {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Check")
                    }
                }
                .disabled(busy)
                .help("Check for updates")
            }
        } content: {
            Text("Version \(version).")
                .foregroundStyle(.secondary)

            if let latest, latest.isNewer(than: version) {
                HStack(spacing: 12) {
                    Button("Install \(latest.version) and Restart") {
                        Task { await install(latest) }
                    }
                    .disabled(busy)
                    Button {
                        NSWorkspace.shared.open(latest.page)
                    } label: {
                        Label("Release notes", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .pointingCursor()
                }
            }
        }
    }

    @ViewBuilder
    private var result: some View {
        if let failure {
            Label(failure, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(palette.warning)
        } else if let latest {
            if latest.isNewer(than: version) {
                Label("\(latest.version) is out", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(palette.accent)
            } else {
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(palette.success)
            }
        }
    }

    private func check() async {
        busy = true
        latest = nil
        failure = nil
        defer { busy = false }
        do {
            latest = try await checker.latestRelease()
        } catch {
            failure = error.localizedDescription
        }
    }

    private func install(_ release: Release) async {
        busy = true
        failure = nil
        defer { busy = false }
        do {
            try await installer.install(release)
            NSApp.terminate(nil)
        } catch {
            failure = error.localizedDescription
        }
    }
}
