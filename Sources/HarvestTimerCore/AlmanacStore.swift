import Foundation

/// Almanac's last answer, in a JSON file of its own.
///
/// Persisting this — not just holding it in memory for the run — is what
/// lets a constraint survive from the day it was fetched as "tomorrow"
/// through to the day it covers, once Almanac's own `next_constraints` stops
/// returning it. See `AlmanacBook.received`.
///
/// Losing the cache is a nuisance, not a disaster, so a failed read or write
/// is quiet: the app carries on with whatever it has, same as `GoalsStore`.
public struct AlmanacStore {
    private let url: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.url = directory.appendingPathComponent("almanac.json")
    }

    public func load() -> AlmanacBook {
        guard let data = try? Data(contentsOf: url),
              let book = try? JSONDecoder().decode(AlmanacBook.self, from: data) else {
            return AlmanacBook()
        }
        return book
    }

    public func save(_ book: AlmanacBook) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(book) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
