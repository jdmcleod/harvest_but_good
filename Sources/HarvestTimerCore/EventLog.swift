import Foundation

/// The record of when timers actually started and stopped, one file per day.
///
/// Harvest stores a total, not a history, so this is the only account of how a
/// day was spent — which is what the timeline draws. Each event is one line,
/// appended, so writing the hundredth event of a day costs the same as the
/// first and no reader is ever holding a half-written file.
public struct EventLog {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HarvestTimer", isDirectory: true)
    }

    public func events(forDay day: Day) -> [TimerEvent] {
        guard let data = try? Data(contentsOf: fileURL(forDay: day)) else { return [] }
        // Days written before the log became append-only hold a JSON array.
        if let events = try? Self.decoder.decode([TimerEvent].self, from: data) {
            return events
        }
        return data
            .split(separator: UInt8(ascii: "\n"))
            .compactMap { try? Self.decoder.decode(TimerEvent.self, from: Data($0)) }
    }

    public func append(_ event: TimerEvent, day: Day) {
        guard let line = try? Self.encoder.encode(event) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(forDay: day)
        if holdsLegacyArray(at: url) {
            rewriteAsLines(at: url, day: day)
        }
        appendLine(line, to: url)
    }

    private func fileURL(forDay day: Day) -> URL {
        directory.appendingPathComponent("events-\(day.name).json")
    }

    /// Appends with O_APPEND, so the write lands at the end of the file as one
    /// step rather than reading, rewriting, and replacing the whole day.
    private func appendLine(_ line: Data, to url: URL) {
        var bytes = line
        bytes.append(UInt8(ascii: "\n"))
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        bytes.withUnsafeBytes { buffer in
            _ = write(descriptor, buffer.baseAddress, buffer.count)
        }
    }

    private func holdsLegacyArray(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let start = try? handle.read(upToCount: 8) else { return false }
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0a, 0x0d]
        return start.first { !whitespace.contains($0) } == UInt8(ascii: "[")
    }

    /// Turns a day's old JSON array into one event per line, once, so the
    /// appends after it have somewhere to land.
    private func rewriteAsLines(at url: URL, day: Day) {
        let existing = events(forDay: day)
        var lines = Data()
        for event in existing {
            guard let line = try? Self.encoder.encode(event) else { continue }
            lines.append(line)
            lines.append(UInt8(ascii: "\n"))
        }
        try? lines.write(to: url, options: .atomic)
    }
}
