import Foundation
import HarvestTimerCore

var failures = 0
var passes = 0

/// The test currently running, so a failed expectation can say where it came from.
private var currentTest = "<no test>"

func expect(
    _ condition: Bool,
    _ message: String,
    file: String = #file,
    line: Int = #line
) {
    if condition {
        passes += 1
    } else {
        failures += 1
        let filename = URL(fileURLWithPath: file).lastPathComponent
        print("FAIL [\(filename):\(line)] \(currentTest): \(message)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    currentTest = name
    do {
        try body()
    } catch {
        failures += 1
        print("FAIL [\(name)] threw \(error)")
    }
    currentTest = "<no test>"
}

func test(_ name: String, _ body: () async throws -> Void) async {
    currentTest = name
    do {
        try await body()
    } catch {
        failures += 1
        print("FAIL [\(name)] threw \(error)")
    }
    currentTest = "<no test>"
}

/// Fixed clock every suite hangs its timestamps off.
let base = Date(timeIntervalSince1970: 1_754_470_800)

/// A day written out, for fixtures that want a fixed date.
func day(_ name: String) -> Day {
    Day(name: name)!
}
