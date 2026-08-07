import Foundation
import Testing

@testable import HarvestTimerCore

/// Checks one thing, naming what was expected when it does not hold.
///
/// A thin cover over `#expect` so a failure points at the line that called
/// this rather than at the harness, and so the name of the case it came from
/// travels with the message.
func expect(
    _ condition: Bool,
    _ message: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(condition, "\(currentCase): \(message)", sourceLocation: sourceLocation)
}

/// The case now running, so a failed expectation can say where it came from.
/// Task-local rather than global: swift-testing runs suites side by side, and
/// a shared variable would hand one suite's name to another's failure.
@TaskLocal private var currentCase = "<no case>"

/// One case within a suite. `#expect` carries on after a failure, so the rest
/// of a suite still runs and reports.
func test(_ name: String, _ body: () throws -> Void) {
    $currentCase.withValue(name) {
        #expect(throws: Never.self, "\(name) threw") { try body() }
    }
}

func test(_ name: String, _ body: () async throws -> Void) async {
    await $currentCase.withValue(name) {
        await #expect(throws: Never.self, "\(name) threw") { try await body() }
    }
}

/// Fixed clock every suite hangs its timestamps off.
let base = Date(timeIntervalSince1970: 1_754_470_800)

/// A day written out, for fixtures that want a fixed date.
func day(_ name: String) -> Day {
    Day(name: name)!
}
