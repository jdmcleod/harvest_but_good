import Foundation

/// Names given to the timeline's breaks, in a JSON file of their own,
/// keyed by each break's id.
///
/// Losing a name is a nuisance, not a disaster, so a failed read or write
/// is quiet: the app carries on with whatever it has.
public struct BreakTitlesStore {
    private let url: URL
    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
        self.url = directory.appendingPathComponent("break-titles.json")
    }

    public func load() -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let titles = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return titles
    }

    public func save(_ titles: [String: String]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(titles) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
