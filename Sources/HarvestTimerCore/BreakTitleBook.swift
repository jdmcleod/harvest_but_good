import Foundation
import Observation

/// The names given to the timeline's breaks, keyed by each break's id.
@MainActor
@Observable
public final class BreakTitleBook {
    public private(set) var titles: [String: String] = [:]
    private let store: BreakTitlesStore

    public init(store: BreakTitlesStore) {
        self.store = store
        titles = store.load()
    }

    public func title(forBreakId id: String) -> String? {
        titles[id]
    }

    /// Names a break on the timeline. A blank title takes the name away.
    public func setTitle(_ title: String, forBreakId id: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            titles.removeValue(forKey: id)
        } else {
            titles[id] = trimmed
        }
        store.save(titles)
    }
}
