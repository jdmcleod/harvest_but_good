import Foundation

var failures = 0
var passes = 0

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
        print("FAIL [\(filename):\(line)] \(message)")
    }
}

func test(_ name: String, _ body: () throws -> Void) {
    do {
        try body()
    } catch {
        failures += 1
        print("FAIL [\(name)] threw \(error)")
    }
}

/// Fixed clock every suite hangs its timestamps off.
let base = Date(timeIntervalSince1970: 1_754_470_800)
