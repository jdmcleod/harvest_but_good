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

public enum TimelineBuilder {
    public static func blocks(
        from events: [TimerEvent],
        now: Date,
        runningEntryIds: Set<Int64>
    ) -> [TimelineBlock] {
        var blocks: [TimelineBlock] = []
        var openStarts: [Int64: TimerEvent] = [:]

        for event in events.sorted(by: { $0.timestamp < $1.timestamp }) {
            switch event.action {
            case .start:
                for open in openStarts.values where open.entryId != event.entryId {
                    blocks.append(TimelineBlock(
                        entryId: open.entryId,
                        projectId: open.projectId,
                        start: open.timestamp,
                        end: event.timestamp
                    ))
                }
                openStarts = [event.entryId: event]
            case .stop:
                guard let open = openStarts.removeValue(forKey: event.entryId) else { continue }
                blocks.append(TimelineBlock(
                    entryId: open.entryId,
                    projectId: open.projectId,
                    start: open.timestamp,
                    end: event.timestamp
                ))
            case .edit, .delete:
                continue
            }
        }

        for open in openStarts.values
        where open.timestamp <= now && runningEntryIds.contains(open.entryId) {
            let endOfDay = Calendar.current.startOfDay(for: open.timestamp).addingTimeInterval(86_400)
            blocks.append(TimelineBlock(
                entryId: open.entryId,
                projectId: open.projectId,
                start: open.timestamp,
                end: min(now, endOfDay)
            ))
        }

        return blocks.sorted { $0.start < $1.start }
    }

    public static func modifiedEntryIds(from events: [TimerEvent]) -> Set<Int64> {
        Set(events.filter { $0.action == .edit || $0.action == .delete }.map(\.entryId))
    }

    public static func startCounts(from events: [TimerEvent]) -> [Int64: Int] {
        events.filter { $0.action == .start }.reduce(into: [:]) { counts, event in
            counts[event.entryId, default: 0] += 1
        }
    }
}
