import Foundation

/// Turns the timer event log into the blocks the day timeline draws.
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
