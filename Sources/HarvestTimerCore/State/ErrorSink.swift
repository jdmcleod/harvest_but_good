import Foundation
import Observation

/// The one error banner. Everything that talks to Harvest reports its failures
/// here, so a caller never has to decide where a message goes and the window
/// has a single place to read one from.
@MainActor
@Observable
public final class ErrorSink {
    public var message: String?

    public init() {}

    public func clear() {
        message = nil
    }

    /// Runs `work`, putting any failure in the banner.
    func run(_ work: () async throws -> Void) async {
        do {
            try await work()
        } catch {
            message = error.localizedDescription
        }
    }
}
