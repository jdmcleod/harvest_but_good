import Foundation

public struct EventLog {
    let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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

    public func events(forDay day: String) -> [TimerEvent] {
        guard let data = try? Data(contentsOf: fileURL(forDay: day)),
              let events = try? Self.decoder.decode([TimerEvent].self, from: data) else {
            return []
        }
        return events
    }

    public func append(_ event: TimerEvent, day: String) {
        var all = events(forDay: day)
        all.append(event)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(all) {
            try? data.write(to: fileURL(forDay: day), options: .atomic)
        }
    }

    private func fileURL(forDay day: String) -> URL {
        directory.appendingPathComponent("events-\(day).json")
    }
}
